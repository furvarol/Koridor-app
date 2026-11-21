import 'dart:math';

/// Bir ortalama hız koridoru: giriş noktası + yön, çıkış noktası, limit.
class Corridor {
  final String id;
  String name;
  double startLat;
  double startLng;
  double startBearing; // 0-360, giriş yönü
  double endLat;
  double endLng;
  int limitKmh;
  double lengthM; // yol boyunca ölçülen uzunluk
  List<List<double>> track; // kayıt sırasındaki iz [lat, lng]

  // Resmi (bakanlık) koridorların sahada doğrulanması: sürücünün işaretlediği
  // giriş/çıkış tabelası konumları ile resmi giriş/çıkış arasındaki farklar.
  String? verify; // 'ok' (doğrulandı) | 'fail' (doğrulanmadı) | null (bakılmadı)
  double? verifyStartM;
  double? verifyEndM;
  double? verifyLenM; // sürücünün kaydettiği uzunluk
  String? verifiedAt;
  List<double>? signStart; // [lat, lng]
  List<double>? signEnd;

  bool get isOfficial => id.startsWith('icisleri-');

  Corridor({
    required this.id,
    required this.name,
    required this.startLat,
    required this.startLng,
    required this.startBearing,
    required this.endLat,
    required this.endLng,
    required this.limitKmh,
    required this.lengthM,
    this.track = const [],
    this.verify,
    this.verifyStartM,
    this.verifyEndM,
    this.verifyLenM,
    this.verifiedAt,
    this.signStart,
    this.signEnd,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'startLat': startLat,
        'startLng': startLng,
        'startBearing': startBearing,
        'endLat': endLat,
        'endLng': endLng,
        'limitKmh': limitKmh,
        'lengthM': lengthM,
        'track': track,
        if (verify != null) 'verify': verify,
        if (verifyStartM != null) 'verifyStartM': verifyStartM,
        if (verifyEndM != null) 'verifyEndM': verifyEndM,
        if (verifyLenM != null) 'verifyLenM': verifyLenM,
        if (verifiedAt != null) 'verifiedAt': verifiedAt,
        if (signStart != null) 'signStart': signStart,
        if (signEnd != null) 'signEnd': signEnd,
      };

  factory Corridor.fromJson(Map<String, dynamic> j) => Corridor(
        id: j['id'],
        name: j['name'],
        startLat: (j['startLat'] as num).toDouble(),
        startLng: (j['startLng'] as num).toDouble(),
        startBearing: (j['startBearing'] as num).toDouble(),
        endLat: (j['endLat'] as num).toDouble(),
        endLng: (j['endLng'] as num).toDouble(),
        limitKmh: j['limitKmh'],
        lengthM: (j['lengthM'] as num).toDouble(),
        track: (j['track'] as List? ?? [])
            .map<List<double>>(
                (p) => [(p[0] as num).toDouble(), (p[1] as num).toDouble()])
            .toList(),
        verify: j['verify'] as String?,
        verifyStartM: (j['verifyStartM'] as num?)?.toDouble(),
        verifyEndM: (j['verifyEndM'] as num?)?.toDouble(),
        verifyLenM: (j['verifyLenM'] as num?)?.toDouble(),
        verifiedAt: j['verifiedAt'] as String?,
        signStart: _pt(j['signStart']),
        signEnd: _pt(j['signEnd']),
      );

  static List<double>? _pt(Object? v) =>
      v is List && v.length == 2 ? [(v[0] as num).toDouble(), (v[1] as num).toDouble()] : null;
}

/// Tamamlanmış bir koridor geçişi.
class Passage {
  final String corridorId;
  final String corridorName;
  final DateTime startedAt;
  final DateTime endedAt;
  final double distanceM;
  final int limitKmh;
  final double maxSpeedKmh;

  Passage({
    required this.corridorId,
    required this.corridorName,
    required this.startedAt,
    required this.endedAt,
    required this.distanceM,
    required this.limitKmh,
    required this.maxSpeedKmh,
  });

  double get avgKmh {
    final s = endedAt.difference(startedAt).inMilliseconds / 1000.0;
    return s <= 0 ? 0 : distanceM / s * 3.6;
  }

  bool get withinLimit => avgKmh <= limitKmh;

  Map<String, dynamic> toJson() => {
        'corridorId': corridorId,
        'corridorName': corridorName,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt.toIso8601String(),
        'distanceM': distanceM,
        'limitKmh': limitKmh,
        'maxSpeedKmh': maxSpeedKmh,
      };

  factory Passage.fromJson(Map<String, dynamic> j) => Passage(
        corridorId: j['corridorId'],
        corridorName: j['corridorName'],
        startedAt: DateTime.parse(j['startedAt']),
        endedAt: DateTime.parse(j['endedAt']),
        distanceM: (j['distanceM'] as num).toDouble(),
        limitKmh: j['limitKmh'],
        maxSpeedKmh: (j['maxSpeedKmh'] as num).toDouble(),
      );
}

/// İki yön arasındaki en küçük açı farkı (derece).
double bearingDiff(double a, double b) {
  final d = (a - b).abs() % 360;
  return min(d, 360 - d);
}
