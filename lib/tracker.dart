import 'dart:async';

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

  final FlutterTts _tts = FlutterTts();
  StreamSubscription<Position>? _sub;

  List<Corridor> corridors = [];
  List<Passage> passages = [];

  TrackerMode mode = TrackerMode.idle;
  Position? lastPos;
  double? heading; // derece
  String status = 'Hazır';
  bool running = false;
  bool voiceOn = true; // sesli uyarılar açık mı

  // Aktif koridor durumu
  Corridor? active;
  DateTime? startedAt;
  double distanceM = 0;
  double maxSpeedKmh = 0;
  DateTime? _lastWarning;
  final Map<String, DateTime> _lastFinished = {};

  // Kayıt modu durumu
  Position? _recStart;
  double? _recBearing;
  DateTime? _recStartedAt;
  double _recLenM = 0;
  final List<List<double>> _recTrack = [];

  // --- Türetilmiş değerler ---
  Duration get elapsed =>
      startedAt == null ? Duration.zero : DateTime.now().difference(startedAt!);

  double get avgKmh {
    final s = elapsed.inMilliseconds / 1000.0;
    return s < 1 ? 0 : distanceM / s * 3.6;
  }

  double get currentKmh => (lastPos?.speed ?? 0) * 3.6;

  double get remainingM =>
      active == null ? 0 : (active!.lengthM - distanceM).clamp(0, double.infinity);

  /// Kalan mesafede ortalamayı limitin altında tutmak için izin verilen azami hız.
  /// Negatif/anlamsız çıkarsa (zaten limit aşılmışsa) 0 döner, sonsuzsa 999.
  double get allowedKmh {
    if (active == null) return 0;
    final limitMs = active!.limitKmh / 3.6;
    final allowedTotalS = active!.lengthM / limitMs;
    final remainingS = allowedTotalS - elapsed.inMilliseconds / 1000.0;
    if (remainingM < 1) return 999;
    if (remainingS <= 0) return 0;
    return (remainingM / remainingS * 3.6).clamp(0, 999);
  }

  double get progress =>
      active == null || active!.lengthM <= 0 ? 0 : (distanceM / active!.lengthM).clamp(0, 1);

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
    if (mode == TrackerMode.inCorridor) _abort('Takip durduruldu');
    status = 'Durduruldu';
    notifyListeners();
  }

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

    switch (mode) {
      case TrackerMode.idle:
        if (usable) _checkEntry(p);
        break;
      case TrackerMode.inCorridor:
        if (usable) _advance(p);
        break;
      case TrackerMode.recording:
        if (usable && lastPos != null) {
          final prev = _recTrack.last;
          _recLenM += Geolocator.distanceBetween(prev[0], prev[1], p.latitude, p.longitude);
          _recTrack.add([p.latitude, p.longitude]);
        }
        break;
    }
    lastPos = p;
    notifyListeners();
  }

  // ---------------- Otomatik tetikleme ----------------

  void _checkEntry(Position p) {
    if (heading == null) return;
    for (final c in corridors) {
      final last = _lastFinished[c.id];
      if (last != null && DateTime.now().difference(last) < retriggerCooldown) continue;
      final d = Geolocator.distanceBetween(p.latitude, p.longitude, c.startLat, c.startLng);
      if (d <= triggerRadiusM && bearingDiff(heading!, c.startBearing) <= maxBearingDiff) {
        _enter(c, p);
        return;
      }
    }
  }

  void _enter(Corridor c, Position p) {
    mode = TrackerMode.inCorridor;
    active = c;
    startedAt = p.timestamp;
    distanceM = 0;
    maxSpeedKmh = 0;
    _lastWarning = null;
    status = '${c.name} koridorundasın';
    _speak('${c.name} koridoruna girdin. Limit ${c.limitKmh}.');
  }

  void _advance(Position p) {
    final c = active!;
    if (lastPos != null) {
      final step = Geolocator.distanceBetween(
          lastPos!.latitude, lastPos!.longitude, p.latitude, p.longitude);
      if (step < 300) distanceM += step; // GPS sıçramasını yoksay
    }
    final kmh = p.speed * 3.6;
    if (kmh > maxSpeedKmh) maxSpeedKmh = kmh;

    final dEnd = Geolocator.distanceBetween(p.latitude, p.longitude, c.endLat, c.endLng);
    if (dEnd <= triggerRadiusM && distanceM > c.lengthM * 0.5) {
      _finish(p);
      return;
    }
    // Koridordan çıkılmış görünüyor (uzunluğun 2 katı gidildi): iptal
    if (distanceM > c.lengthM * 2 + 2000) {
      _abort('Koridor çıkışı bulunamadı, iptal edildi');
      return;
    }
    _maybeWarn(c);
  }

  void _maybeWarn(Corridor c) {
    final now = DateTime.now();
    if (_lastWarning != null && now.difference(_lastWarning!) < const Duration(seconds: 20)) {
      return;
    }
    if (elapsed < const Duration(seconds: 15)) return;
    if (avgKmh > c.limitKmh) {
      _lastWarning = now;
      final a = allowedKmh.round();
      _speak(a <= 0
          ? 'Dikkat, ortalama ${avgKmh.round()}. Limit aşıldı, yavaşla.'
          : 'Dikkat, ortalama ${avgKmh.round()}. En fazla $a ile git.');
    } else if (avgKmh > c.limitKmh - 3) {
      _lastWarning = now;
      _speak('Ortalama limite yaklaştı, ${avgKmh.round()}.');
    }
  }

  void _finish(Position p) {
    final c = active!;
    final pas = Passage(
      corridorId: c.id,
      corridorName: c.name,
      startedAt: startedAt!,
      endedAt: p.timestamp,
      distanceM: distanceM,
      limitKmh: c.limitKmh,
      maxSpeedKmh: maxSpeedKmh,
    );
    passages.insert(0, pas);
    Storage.savePassages(passages);
    _lastFinished[c.id] = DateTime.now();
    _speak(pas.withinLimit
        ? 'Koridor bitti. Ortalama ${pas.avgKmh.round()}, limitin altında.'
        : 'Koridor bitti. Ortalama ${pas.avgKmh.round()}, limit aşıldı.');
    status = 'Son geçiş: ${c.name} — ort. ${pas.avgKmh.round()} km/s';
    _reset();
  }

  void _abort(String why) {
    if (active != null) _lastFinished[active!.id] = DateTime.now();
    status = why;
    _reset();
  }

  void _reset() {
    mode = TrackerMode.idle;
    active = null;
    startedAt = null;
    distanceM = 0;
    notifyListeners();
  }

  // ---------------- Koridor kaydı (sürerken) ----------------

  String? beginRecording() {
    if (lastPos == null) return 'Henüz konum alınamadı.';
    if (heading == null) return 'Yön belirlenemedi; biraz ilerleyip tekrar dene.';
    if (mode == TrackerMode.inCorridor) return 'Koridor içindeyken kayıt başlatılamaz.';
    mode = TrackerMode.recording;
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

  /// Kaydı bitirir ve koridoru döndürür (isim/limit sonra ekranda sorulur).
  Corridor? endRecording(String name, int limitKmh) {
    if (mode != TrackerMode.recording || _recStart == null || lastPos == null) return null;
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
      endLat: lastPos!.latitude,
      endLng: lastPos!.longitude,
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
    mode = TrackerMode.idle;
    status = 'Koridor iki yönlü kaydedildi: ${(len / 1000).toStringAsFixed(1)} km';
    _speak('Koridor iki yönlü kaydedildi.');
    notifyListeners();
    return c;
  }

  void cancelRecording() {
    if (mode == TrackerMode.recording) {
      mode = TrackerMode.idle;
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

  Future<void> updateCorridor(Corridor c) async {
    await Storage.saveCorridors(corridors);
    notifyListeners();
  }

  Future<void> deleteCorridor(Corridor c) async {
    corridors.removeWhere((x) => x.id == c.id);
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
