import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';

import 'models.dart';
import 'storage.dart';

enum TrackerMode { idle, inCorridor, recording }

/// Konumu sürekli dinler; koridor girişini otomatik yakalar, ortalama hızı
/// hesaplar, gerekirse sesli uyarır ve çıkışta geçişi kaydeder.
class Tracker extends ChangeNotifier {
  // --- Ayarlar ---
  static const double triggerRadiusM = 80; // giriş/çıkış yakalama yarıçapı
  static const double maxBearingDiff = 35; // yön toleransı (derece)
  static const double maxAccuracyM = 40; // daha kötü GPS noktaları atlanır
  static const double minSpeedForHeading = 3; // m/s, yön güvenilirliği için
  static const Duration retriggerCooldown = Duration(minutes: 3);
  // Giriş, başlangıç noktasının yanı sıra izin ilk bu kadar metresinde de
  // (o noktadaki yol yönüyle) yakalanır. Resmi verideki kaymış girişler için.
  static const double entryWindowM = 1500;
  // Bu kadar metre izden uzakta bu kadar ardışık konum: koridordan çıkılmış.
  static const double offTrackM = 250;
  static const int offTrackCount = 15;
  // Bu kadar ardışık konumda yön izin tersineyse (>90°) koridor bırakılır.
  static const int wrongDirCount = 5;
  // Aday koridor, iz üzerinde doğru yönde bu kadar gidilince onaylanır
  // (anons ve ekran ondan sonra; ortalama yine giriş anından hesaplanır).
  static const double confirmM = 200;

  final FlutterTts _tts = FlutterTts();
  StreamSubscription<Position>? _sub;

  List<Corridor> corridors = [];
  List<Passage> passages = [];

  bool _recording = false;
  Position? lastPos;
  double? heading; // derece
  String status = 'Hazır';
  bool running = false;
  bool voiceOn = true; // sesli uyarılar açık mı

  /// İzlenen koridorlar: onaylanmış olanlar ve henüz sessiz adaylar.
  final List<CorridorRun> runs = [];

  /// Onaylanmış (ekranda gösterilen, uyarı veren) koridorlar.
  List<CorridorRun> get confirmedRuns => runs.where((r) => r.confirmed).toList();
  DateTime? _lastWarning;
  final Map<String, DateTime> _lastFinished = {};
  final Map<String, TrackGeo> _geo = {};

  // Kayıt modu durumu
  Position? _recStart;
  double? _recBearing;
  DateTime? _recStartedAt;
  Position? _recEnd; // "Bitiş"e basıldığı an (çıkış tabelası)
  double _recLenM = 0;
  final List<List<double>> _recTrack = [];

  TrackerMode get mode => _recording
      ? TrackerMode.recording
      : runs.any((r) => r.confirmed)
          ? TrackerMode.inCorridor
          : TrackerMode.idle;

  /// Ekranda gösterilen koridor: kalan yolda izin verilen hızı en düşük olan.
  CorridorRun? get primary {
    final list = confirmedRuns;
    if (list.isEmpty) return null;
    final now = DateTime.now();
    final sorted = list
      ..sort((a, b) {
        final c = a.allowedKmh(now).compareTo(b.allowedKmh(now));
        return c != 0 ? c : a.remainingM.compareTo(b.remainingM);
      });
    return sorted.first;
  }

  /// Ekrandaki koridor dışındaki paralel koridorlar.
  List<CorridorRun> get others {
    final p = primary;
    return confirmedRuns.where((r) => !identical(r, p)).toList();
  }

  // --- Türetilmiş değerler (ekrandaki koridor için) ---
  Corridor? get active => primary?.corridor;
  Duration get elapsed => primary?.elapsed(DateTime.now()) ?? Duration.zero;
  double get avgKmh => primary?.avgKmh(DateTime.now()) ?? 0;
  double get currentKmh => (lastPos?.speed ?? 0) * 3.6;
  double get distanceM => primary?.distanceM ?? 0;
  double get remainingM => primary?.remainingM ?? 0;
  double get allowedKmh => primary?.allowedKmh(DateTime.now()) ?? 0;
  double get progress => primary?.progress ?? 0;

  Future<void> init() async {
    corridors = await Storage.loadCorridors();
    passages = await Storage.loadPassages();
    final settings = await Storage.loadSettings();
    voiceOn = settings['voiceOn'] as bool? ?? true;
    await _tts.setLanguage('tr-TR');
    await _tts.setSpeechRate(0.5);
    notifyListeners();
  }

  // ---------------- Konum akışı ----------------

  Future<String?> start() async {
    if (running) return null;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      return 'Konum izni verilmedi.';
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      return 'Konum servisi kapalı.';
    }
    final settings = AndroidSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 3,
      intervalDuration: Duration(seconds: 1),
      foregroundNotificationConfig: ForegroundNotificationConfig(
        notificationTitle: 'Koridor aktif',
        notificationText: 'Ortalama hız koridorları izleniyor',
        enableWakeLock: true,
        notificationIcon: AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
      ),
    );
    _sub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(_onPosition, onError: (e) {
      status = 'Konum hatası: $e';
      notifyListeners();
    });
    running = true;
    status = 'Koridor bekleniyor';
    notifyListeners();
    return null;
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    running = false;
    for (final r in List.of(runs)) {
      _lastFinished[r.corridor.id] = DateTime.now();
    }
    runs.clear();
    status = 'Durduruldu';
    notifyListeners();
  }

  /// Testler için: konum akışı yerine elle konum verir.
  @visibleForTesting
  void feed(Position p) => _onPosition(p);

  void _onPosition(Position p) {
    // Yön: hızlıyken GPS başlığı, yavaşken önceki noktadan hesapla.
    if (p.speed >= minSpeedForHeading && p.heading >= 0) {
      heading = p.heading;
    } else if (lastPos != null) {
      final d = Geolocator.distanceBetween(
          lastPos!.latitude, lastPos!.longitude, p.latitude, p.longitude);
      if (d > 5) {
        heading = Geolocator.bearingBetween(
                lastPos!.latitude, lastPos!.longitude, p.latitude, p.longitude) %
            360;
      }
    }

    final usable = p.accuracy <= maxAccuracyM;
    if (usable) {
      // Önce süren koridorlar (çıkış), sonra yeni girişler: arka arkaya
      // koridorlarda çıkış noktası bir sonrakinin girişi olabilir.
      final confirmedNow = <CorridorRun>[];
      for (final r in List.of(runs)) {
        _advance(r, p, confirmedNow);
      }
      _checkEntry(p, confirmedNow);
      _announce(confirmedNow);
      if (_recording && _recEnd == null && lastPos != null) {
        final prev = _recTrack.last;
        _recLenM += Geolocator.distanceBetween(prev[0], prev[1], p.latitude, p.longitude);
        _recTrack.add([p.latitude, p.longitude]);
      }
      final pr = primary;
      if (pr != null) _maybeWarn(pr);
    }
    lastPos = p;
    notifyListeners();
  }

  // ---------------- Otomatik tetikleme ----------------

  TrackGeo _geoOf(Corridor c) => _geo.putIfAbsent(c.id, () => TrackGeo(c));

  void _checkEntry(Position p, List<CorridorRun> confirmedNow) {
    if (heading == null) return;
    final now = DateTime.now();
    for (final c in corridors) {
      if (runs.any((r) => r.corridor.id == c.id)) continue;
      final last = _lastFinished[c.id];
      if (last != null && now.difference(last) < retriggerCooldown) continue;
      final offset = _entryOffset(c, p);
      if (offset == null) continue;
      final r = CorridorRun(c, p.timestamp, offset, _geoOf(c));
      runs.add(r);
      // İzi olmayan (eski) koridorlar doğrulanamaz; hemen onaylanır.
      if (r.geo.n < 2) {
        r.confirmed = true;
        confirmedNow.add(r);
      }
    }
  }

  void _announce(List<CorridorRun> entered) {
    if (entered.isEmpty) return;
    _lastWarning = null;
    final all = confirmedRuns;
    status = all.length == 1 ? '${all.first.corridor.name} koridorundasın' : '${all.length} koridor izleniyor';
    final limit = entered.first.corridor.limitKmh;
    _speak(entered.length == 1
        ? '${entered.first.corridor.name} koridoruna girdin. Limit $limit.'
        : '${entered.length} koridora girdin. Limit $limit.');
  }

  /// Bu konum koridorun girişi sayılıyorsa iz üzerindeki konumu (m), değilse null.
  double? _entryOffset(Corridor c, Position p) {
    final d0 = Geolocator.distanceBetween(p.latitude, p.longitude, c.startLat, c.startLng);
    if (d0 <= triggerRadiusM && bearingDiff(heading!, c.startBearing) <= maxBearingDiff) {
      return 0;
    }
    final g = _geoOf(c);
    if (g.n < 2) return null;
    for (var i = 0; i < g.n - 1 && g.along[i] <= entryWindowM; i++) {
      final d = _fastDist(p.latitude, p.longitude, g.lat[i], g.lng[i]);
      if (d <= triggerRadiusM && bearingDiff(heading!, g.bearing[i]) <= maxBearingDiff) {
        return g.along[i];
      }
    }
    return null;
  }

  void _advance(CorridorRun r, Position p, List<CorridorRun> confirmedNow) {
    final c = r.corridor;
    if (lastPos != null) {
      final step = Geolocator.distanceBetween(
          lastPos!.latitude, lastPos!.longitude, p.latitude, p.longitude);
      if (step < 300) r.distanceM += step; // GPS sıçramasını yoksay
    }
    final kmh = p.speed * 3.6;
    if (kmh > r.maxSpeedKmh) r.maxSpeedKmh = kmh;

    final dEnd = Geolocator.distanceBetween(p.latitude, p.longitude, c.endLat, c.endLng);
    if (r.confirmed && dEnd <= triggerRadiusM && r.distanceM > r.lengthM * 0.5) {
      _finish(r, p);
      return;
    }
    if (r.geo.n >= 2) {
      // İzden uzaklaşma ya da ters yönde gitme: yanlış aday veya yoldan çıkış.
      final (d, i) = r.geo.nearest(p.latitude, p.longitude);
      r.offTrack = d > offTrackM ? r.offTrack + 1 : 0;
      final h = heading;
      if (h != null && p.speed >= minSpeedForHeading) {
        r.wrongDir = bearingDiff(h, r.geo.bearing[i]) > 90 ? r.wrongDir + 1 : 0;
      }
      if (r.offTrack >= offTrackCount || r.wrongDir >= wrongDirCount) {
        _drop(r, 'Koridor güzergâhından çıkıldı');
        return;
      }
      if (!r.confirmed &&
          r.distanceM >= confirmM &&
          r.offTrack == 0 &&
          r.wrongDir == 0 &&
          d <= triggerRadiusM) {
        r.confirmed = true;
        confirmedNow.add(r);
      }
    }
    // Koridordan çıkılmış görünüyor (uzunluğun 2 katı gidildi): iptal
    if (r.distanceM > r.lengthM * 2 + 2000) {
      _drop(r, 'Koridor çıkışı bulunamadı, iptal edildi');
    }
  }

  void _maybeWarn(CorridorRun r) {
    final now = DateTime.now();
    if (_lastWarning != null && now.difference(_lastWarning!) < const Duration(seconds: 20)) {
      return;
    }
    if (r.elapsed(now) < const Duration(seconds: 15)) return;
    final avg = r.avgKmh(now);
    final limit = r.corridor.limitKmh;
    if (avg > limit) {
      _lastWarning = now;
      final a = r.allowedKmh(now).round();
      _speak(a <= 0
          ? 'Dikkat, ortalama ${avg.round()}. Limit aşıldı, yavaşla.'
          : 'Dikkat, ortalama ${avg.round()}. En fazla $a ile git.');
    } else if (avg > limit - 3) {
      _lastWarning = now;
      _speak('Ortalama limite yaklaştı, ${avg.round()}.');
    }
  }

  void _finish(CorridorRun r, Position p) {
    final c = r.corridor;
    final pas = Passage(
      corridorId: c.id,
      corridorName: c.name,
      startedAt: r.startedAt,
      endedAt: p.timestamp,
      distanceM: r.distanceM,
      limitKmh: c.limitKmh,
      maxSpeedKmh: r.maxSpeedKmh,
    );
    passages.insert(0, pas);
    Storage.savePassages(passages);
    runs.remove(r);
    _lastFinished[c.id] = DateTime.now();
    _speak(pas.withinLimit
        ? '${c.name} bitti. Ortalama ${pas.avgKmh.round()}, limitin altında.'
        : '${c.name} bitti. Ortalama ${pas.avgKmh.round()}, limit aşıldı.');
    status = 'Son geçiş: ${c.name} — ort. ${pas.avgKmh.round()} km/s';
  }

  void _drop(CorridorRun r, String why) {
    runs.remove(r);
    if (!r.confirmed) return; // sessiz aday: iz bırakmadan düşer
    _lastFinished[r.corridor.id] = DateTime.now();
    if (confirmedRuns.isEmpty) status = why;
  }

  // ---------------- Koridor kaydı (sürerken) ----------------

  String? beginRecording() {
    if (lastPos == null) return 'Henüz konum alınamadı.';
    if (heading == null) return 'Yön belirlenemedi; biraz ilerleyip tekrar dene.';
    if (_recording) return 'Zaten kayıt yapılıyor.';
    // Koridor içindeyken de kayıt yapılabilir (resmi koridorla karşılaştırmak için).
    _recording = true;
    _recStart = lastPos;
    _recBearing = heading;
    _recStartedAt = lastPos!.timestamp;
    _recLenM = 0;
    _recTrack
      ..clear()
      ..add([lastPos!.latitude, lastPos!.longitude]);
    status = 'Koridor kaydediliyor…';
    _speak('Koridor başlangıcı kaydedildi.');
    notifyListeners();
    return null;
  }

  /// "Bitiş"e basıldı: çıkış tabelasının konumunu sabitler, izi dondurur.
  void markRecordingEnd() {
    if (_recording && lastPos != null) _recEnd ??= lastPos;
    notifyListeners();
  }

  /// "Bitiş" diyaloğundan vazgeçildi: kayıt sürer.
  void resumeRecording() {
    _recEnd = null;
    notifyListeners();
  }

  // ---------------- Resmi koridor doğrulama ----------------

  static const double verifyToleranceM = 200; // tabela ile resmi nokta arası
  static const double verifyMatchMaxM = 2000; // eşleşme için en fazla uzaklık

  /// Kaydedilen giriş/çıkış tabelalarına en uygun resmi koridoru bulur.
  VerifyMatch? findOfficialMatch() {
    final s = _recStart;
    final e = _recEnd ?? lastPos;
    if (!_recording || s == null || e == null) return null;
    final recBearing =
        Geolocator.bearingBetween(s.latitude, s.longitude, e.latitude, e.longitude) % 360;
    VerifyMatch? best;
    for (final c in corridors.where((c) => c.isOfficial)) {
      final dS = Geolocator.distanceBetween(s.latitude, s.longitude, c.startLat, c.startLng);
      final dE = Geolocator.distanceBetween(e.latitude, e.longitude, c.endLat, c.endLng);
      if (dS > verifyMatchMaxM || dE > verifyMatchMaxM) continue;
      final cb = Geolocator.bearingBetween(c.startLat, c.startLng, c.endLat, c.endLng) % 360;
      if (bearingDiff(recBearing, cb) > 45) continue;
      if (best == null || dS + dE < best.startDiffM + best.endDiffM) {
        best = VerifyMatch(c, dS, dE, recordingLengthM, [s.latitude, s.longitude],
            [e.latitude, e.longitude]);
      }
    }
    return best;
  }

  /// Doğrulama sonucunu resmi koridora işler. [finish] ise kaydı da bitirir
  /// (elle kayıt ayrı koridor olarak saklanmaz).
  Future<void> applyVerification(VerifyMatch m, {bool finish = false}) async {
    final c = m.corridor;
    c.verify = m.ok ? 'ok' : 'fail';
    c.verifyStartM = m.startDiffM;
    c.verifyEndM = m.endDiffM;
    c.verifyLenM = m.recordedLenM;
    c.verifiedAt = DateTime.now().toIso8601String();
    c.signStart = m.signStart;
    c.signEnd = m.signEnd;
    await Storage.saveCorridors(corridors);
    if (finish) {
      _recording = false;
      _recEnd = null;
      status = '${c.name}: ${m.ok ? 'doğrulandı' : 'doğrulanmadı'}';
      _speak(m.ok ? 'Resmi koridor doğrulandı.' : 'Resmi koridor doğrulanmadı.');
    }
    notifyListeners();
  }

  /// Kaydı bitirir ve koridoru döndürür (isim/limit sonra ekranda sorulur).
  Corridor? endRecording(String name, int limitKmh) {
    if (!_recording || _recStart == null || lastPos == null) return null;
    final end = _recEnd ?? lastPos!;
    double len = 0;
    for (var i = 1; i < _recTrack.length; i++) {
      len += Geolocator.distanceBetween(
          _recTrack[i - 1][0], _recTrack[i - 1][1], _recTrack[i][0], _recTrack[i][1]);
    }
    final c = Corridor(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      startLat: _recStart!.latitude,
      startLng: _recStart!.longitude,
      startBearing: _recBearing!,
      endLat: end.latitude,
      endLng: end.longitude,
      limitKmh: limitKmh,
      lengthM: len,
      track: List.of(_recTrack),
    );
    // Çift yön: aynı yolun ters yönü için de koridor oluştur.
    final r = reverseOf(c, id: '${c.id}r');
    corridors.addAll([c, r]);
    Storage.saveCorridors(corridors);
    _lastFinished[c.id] = DateTime.now();
    _lastFinished[r.id] = DateTime.now();
    _recording = false;
    _recEnd = null;
    status = 'Koridor iki yönlü kaydedildi: ${(len / 1000).toStringAsFixed(1)} km';
    _speak('Koridor iki yönlü kaydedildi.');
    notifyListeners();
    return c;
  }

  void cancelRecording() {
    if (_recording) {
      _recording = false;
      _recEnd = null;
      status = 'Kayıt iptal edildi';
      notifyListeners();
    }
  }

  double get recordingLengthM => _recLenM;

  Duration get recordingElapsed => _recStartedAt == null
      ? Duration.zero
      : DateTime.now().difference(_recStartedAt!);

  /// Kayıt başladığından beri ortalama hız.
  double get recordingAvgKmh {
    final s = recordingElapsed.inMilliseconds / 1000.0;
    return s < 1 ? 0 : _recLenM / s * 3.6;
  }

  // ---------------- Ters yön ----------------

  /// Bir koridorun ters yönü: çıkış noktası giriş olur, iz ters çevrilir.
  Corridor reverseOf(Corridor c, {String? id}) {
    final track = c.track.reversed.map((p) => List<double>.of(p)).toList();
    return Corridor(
      id: id ?? '${DateTime.now().millisecondsSinceEpoch}r',
      name: reverseName(c.name),
      startLat: c.endLat,
      startLng: c.endLng,
      startBearing: _startBearingOf(track, c.endLat, c.endLng, (c.startBearing + 180) % 360),
      endLat: c.startLat,
      endLng: c.startLng,
      limitKmh: c.limitKmh,
      lengthM: c.lengthM,
      track: track,
    );
  }

  /// Var olan bir koridora ters yönünü ekler.
  Future<Corridor> addReverse(Corridor c) async {
    final r = reverseOf(c);
    corridors.add(r);
    await Storage.saveCorridors(corridors);
    notifyListeners();
    return r;
  }

  /// İzin başından ~60 m ilerideki noktaya göre giriş yönü; iz yoksa yedek değer.
  static double _startBearingOf(
      List<List<double>> track, double lat, double lng, double fallback) {
    double acc = 0;
    for (var i = 1; i < track.length; i++) {
      acc += Geolocator.distanceBetween(
          track[i - 1][0], track[i - 1][1], track[i][0], track[i][1]);
      if (acc >= 60) {
        return Geolocator.bearingBetween(lat, lng, track[i][0], track[i][1]) % 360;
      }
    }
    if (track.length > 1 && acc > 10) {
      return Geolocator.bearingBetween(lat, lng, track.last[0], track.last[1]) % 360;
    }
    return fallback;
  }

  /// "Siirt–Kurtalan" -> "Kurtalan–Siirt"; ayraç yoksa "(dönüş)" eklenir.
  static String reverseName(String name) {
    for (final sep in ['–', '—', '-']) {
      final parts = name.split(sep);
      if (parts.length == 2 && parts[0].trim().isNotEmpty && parts[1].trim().isNotEmpty) {
        return '${parts[1].trim()}$sep${parts[0].trim()}';
      }
    }
    return '$name (dönüş)';
  }

  // ---------------- Ses ----------------

  Future<void> setVoice(bool on) async {
    voiceOn = on;
    if (!on) {
      try {
        await _tts.stop();
      } catch (_) {}
    }
    notifyListeners();
    await Storage.saveSettings({'voiceOn': on});
  }

  // ---------------- Koridor yönetimi ----------------

  /// APK'ya gömülü resmi koridor listesini ekler; aynı kimlikli olanları atlar.
  /// Eklenen koridor sayısını döndürür.
  Future<int> importCorridors(List<Corridor> list) async {
    final ids = corridors.map((c) => c.id).toSet();
    final fresh = list.where((c) => !ids.contains(c.id)).toList();
    corridors.addAll(fresh);
    await Storage.saveCorridors(corridors);
    notifyListeners();
    return fresh.length;
  }

  Future<void> updateCorridor(Corridor c) async {
    _geo.remove(c.id);
    await Storage.saveCorridors(corridors);
    notifyListeners();
  }

  Future<void> deleteCorridor(Corridor c) async {
    corridors.removeWhere((x) => x.id == c.id);
    runs.removeWhere((r) => r.corridor.id == c.id);
    _geo.remove(c.id);
    await Storage.saveCorridors(corridors);
    notifyListeners();
  }

  Future<void> clearPassages() async {
    passages.clear();
    await Storage.savePassages(passages);
    notifyListeners();
  }

  Future<void> _speak(String text) async {
    if (!voiceOn) return;
    try {
      await _tts.speak(text);
    } catch (_) {}
  }
}

/// Elle kaydedilen tabelaların bir resmi koridorla karşılaştırması.
class VerifyMatch {
  final Corridor corridor;
  final double startDiffM, endDiffM, recordedLenM;
  final List<double> signStart, signEnd;
  VerifyMatch(this.corridor, this.startDiffM, this.endDiffM, this.recordedLenM, this.signStart,
      this.signEnd);

  bool get ok =>
      startDiffM <= Tracker.verifyToleranceM && endDiffM <= Tracker.verifyToleranceM;
}

/// Süren bir koridor geçişi.
class CorridorRun {
  final Corridor corridor;
  final DateTime startedAt;
  /// Giriş izin başından değil de içinden yakalandıysa, atlanan kısım (m).
  final double offsetM;
  final TrackGeo geo;
  double distanceM = 0;
  double maxSpeedKmh = 0;
  int offTrack = 0;
  int wrongDir = 0;
  bool confirmed = false;

  CorridorRun(this.corridor, this.startedAt, this.offsetM, this.geo);

  /// Bu geçişte gidilecek uzunluk.
  double get lengthM => (corridor.lengthM - offsetM).clamp(1, double.infinity).toDouble();

  Duration elapsed(DateTime now) => now.difference(startedAt);

  double avgKmh(DateTime now) {
    final s = elapsed(now).inMilliseconds / 1000.0;
    return s < 1 ? 0 : distanceM / s * 3.6;
  }

  double get remainingM => (lengthM - distanceM).clamp(0, double.infinity).toDouble();

  double get progress => (distanceM / lengthM).clamp(0, 1).toDouble();

  /// Kalan mesafede ortalamayı limitin altında tutmak için izin verilen azami hız.
  /// Zaten limit aşılmışsa 0, kalan yol yoksa 999.
  double allowedKmh(DateTime now) {
    final limitMs = corridor.limitKmh / 3.6;
    final remainingS = lengthM / limitMs - elapsed(now).inMilliseconds / 1000.0;
    if (remainingM < 1) return 999;
    if (remainingS <= 0) return 0;
    return (remainingM / remainingS * 3.6).clamp(0, 999).toDouble();
  }
}

/// Koridor izinin önceden hesaplanmış geometrisi (iz boyunca mesafe, yerel yön).
class TrackGeo {
  final List<double> lat = [], lng = [], along = [], bearing = [];
  int get n => lat.length;

  TrackGeo(Corridor c) {
    double acc = 0;
    for (var i = 0; i < c.track.length; i++) {
      final p = c.track[i];
      if (i > 0) acc += _fastDist(lat.last, lng.last, p[0], p[1]);
      lat.add(p[0]);
      lng.add(p[1]);
      along.add(acc);
    }
    // Yerel yön: ~100 m ilerideki noktaya göre (kısa GPS adımlarındaki gürültüyü yumuşatır).
    var j = 0;
    for (var i = 0; i < n; i++) {
      if (j < i) j = i;
      while (j < n - 1 && along[j] - along[i] < 100) {
        j++;
      }
      bearing.add(j > i
          ? Geolocator.bearingBetween(lat[i], lng[i], lat[j], lng[j]) % 360
          : (i > 0 ? bearing[i - 1] : 0));
    }
  }

  /// İze en yakın uzaklık (m) ve o doğru parçasının başındaki nokta.
  (double, int) nearest(double la, double lo) {
    var best = double.infinity;
    var bi = 0;
    final k = cos(la * pi / 180);
    for (var i = 0; i < n - 1; i++) {
      final ax = (lng[i] - lo) * k, ay = lat[i] - la;
      final bx = (lng[i + 1] - lo) * k, by = lat[i + 1] - la;
      final dx = bx - ax, dy = by - ay;
      final len2 = dx * dx + dy * dy;
      var t = len2 == 0 ? 0.0 : -(ax * dx + ay * dy) / len2;
      t = t.clamp(0.0, 1.0);
      final px = ax + t * dx, py = ay + t * dy;
      final d2 = px * px + py * py;
      if (d2 < best) {
        best = d2;
        bi = i;
      }
    }
    return (sqrt(best) * 111195, bi);
  }
}

/// Kısa mesafeler için hızlı yaklaşık uzaklık (m).
double _fastDist(double la1, double lo1, double la2, double lo2) {
  final k = cos((la1 + la2) / 2 * pi / 180);
  final dx = (lo2 - lo1) * k, dy = la2 - la1;
  return sqrt(dx * dx + dy * dy) * 111195;
}
