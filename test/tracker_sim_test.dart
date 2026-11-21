// Ankara–İzmir resmi koridor verisi üzerinde yolculuk benzetimi:
// konumlar koridor izleri boyunca 25 m aralıkla, 108 km/s hızla verilir.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:koridor/models.dart';
import 'package:koridor/tracker.dart';

late Map<String, Corridor> data;

List<List<double>> trackFrom(String id, {double skipM = 0}) {
  final t = data[id]!.track;
  if (skipM == 0) return t;
  double acc = 0;
  for (var i = 1; i < t.length; i++) {
    acc += Geolocator.distanceBetween(t[i - 1][0], t[i - 1][1], t[i][0], t[i][1]);
    if (acc >= skipM) return t.sublist(i);
  }
  return [];
}

/// Noktaları birleştirip 25 m aralıklı konum dizisine çevirir.
List<Position> drive(List<List<List<double>>> legs, DateTime t0) {
  final pts = <List<double>>[for (final l in legs) ...l];
  final out = <Position>[];
  var t = t0;
  for (var i = 1; i < pts.length; i++) {
    final a = pts[i - 1], b = pts[i];
    final d = Geolocator.distanceBetween(a[0], a[1], b[0], b[1]);
    if (d < 0.5) continue;
    final br = Geolocator.bearingBetween(a[0], a[1], b[0], b[1]) % 360;
    final n = (d / 25).ceil();
    for (var k = 0; k < n; k++) {
      final f = k / n;
      t = t.add(Duration(milliseconds: (d / n / 30 * 1000).round()));
      out.add(Position(
        latitude: a[0] + (b[0] - a[0]) * f,
        longitude: a[1] + (b[1] - a[1]) * f,
        timestamp: t,
        accuracy: 5, altitude: 0, altitudeAccuracy: 0,
        heading: br, headingAccuracy: 0, speed: 30, speedAccuracy: 0,
      ));
    }
  }
  return out;
}

Future<List<String>> run(List<List<List<double>>> legs) async {
  final tr = Tracker();
  tr.corridors = data.values.toList();
  final started = <String>{};
  final live = <String, List>{};
  for (final p in drive(legs, DateTime.now())) {
    tr.feed(p);
    final now = {for (final r in tr.confirmedRuns) r.corridor.id: r};
    for (final e in now.entries) {
      if (!live.containsKey(e.key)) {
        live[e.key] = [e.value.offsetM, p.heading, e.value.distanceM];
      }
      started.add(e.key);
    }
    for (final k in live.keys.toList()) {
      if (!now.containsKey(k)) {
        // ignore: avoid_print
        print('  $k giriş ofset=${(live[k]![0] as double).round()} yön=${(live[k]![1] as double).round()} -> ${tr.passages.isNotEmpty && tr.passages.first.corridorId == k ? "bitti" : "düştü"}');
        live.remove(k);
      }
    }
  }
  final done = tr.passages.reversed.map((p) => p.corridorId).toList();
  // ignore: avoid_print
  print('başlayan: $started');
  // ignore: avoid_print
  print('biten: ${tr.passages.reversed.map((p) => '${p.corridorId} ${(p.distanceM / 1000).toStringAsFixed(1)}km ort ${p.avgKmh.round()}').join(' | ')}');
  // Onaylanan her koridor bitmiş olmalı (yanlış anons yok).
  expect(started.toSet(), done.toSet());
  return done;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tmp = Directory.systemTemp.createTempSync('koridor');
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  m.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (c) async => tmp.path);
  m.setMockMethodCallHandler(const MethodChannel('flutter_tts'), (c) async => 1);

  setUpAll(() {
    final list = jsonDecode(File('koridor-verisi/ankara-izmir.json').readAsStringSync()) as List;
    data = {for (final e in list) e['id']: Corridor.fromJson(e)};
  });

  test('Ankara → İzmir', () async {
    final done = await run([
      trackFrom('icisleri-1433'),
      // 1233'ün girişi ana yoldan ~900 m uzakta; sürücü izin ~1 km sonrasında katılır.
      trackFrom('icisleri-1233', skipM: 1000),
      trackFrom('icisleri-1720'),
      trackFrom('icisleri-1560'),
      trackFrom('icisleri-1563'),
      trackFrom('icisleri-1569'),
    ]);
    expect(done, ['icisleri-1433', 'icisleri-1233', 'icisleri-1720', 'icisleri-1560', 'icisleri-1563', 'icisleri-1569']);
  });

  test('İzmir → Ankara (Afyon\'da iki koridor paralel)', () async {
    final done = await run([
      trackFrom('icisleri-1565'),
      trackFrom('icisleri-1561'),
      trackFrom('icisleri-1724'),
      trackFrom('icisleri-1718'),
      trackFrom('icisleri-1260'),
    ]);
    expect(done.take(4), ['icisleri-1565', 'icisleri-1561', 'icisleri-1724', 'icisleri-1718']);
    expect(done, contains('icisleri-1260'));
    expect(done, contains('icisleri-1234'));
  });

  // Elle kayıt: giriş tabelasında başlat, çıkış tabelasında "Bitiş".
  VerifyMatch? recordAlong(List<List<double>> track) {
    final tr = Tracker();
    tr.corridors = data.values.toList();
    final ps = drive([track], DateTime.now());
    tr.feed(ps.first);
    expect(tr.beginRecording(), isNull);
    for (final p in ps.skip(1)) {
      tr.feed(p);
    }
    tr.markRecordingEnd();
    return tr.findOfficialMatch();
  }

  test('Doğrulama: tabelalar resmi noktalarla örtüşüyor (1720)', () {
    final m = recordAlong(trackFrom('icisleri-1720'));
    expect(m, isNotNull);
    expect(m!.corridor.id, 'icisleri-1720'); // ters yön 1718 değil
    expect(m.ok, isTrue);
    // ignore: avoid_print
    print('1720: giriş ${m.startDiffM.round()} m, çıkış ${m.endDiffM.round()} m');
  });

  test('Doğrulama: resmi giriş kaymış (1233)', () {
    final m = recordAlong(trackFrom('icisleri-1233', skipM: 1000));
    expect(m, isNotNull);
    expect(m!.corridor.id, 'icisleri-1233');
    expect(m.ok, isFalse);
    // ignore: avoid_print
    print('1233: giriş ${m.startDiffM.round()} m, çıkış ${m.endDiffM.round()} m');
  });
}
