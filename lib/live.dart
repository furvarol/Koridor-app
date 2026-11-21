import 'package:flutter/services.dart';

import 'tracker.dart';

/// Koridor içindeyken süren bildirim / Android 16+ durum çubuğu çipi
/// (Live Update). Yerel taraf: LiveNotifier.kt.
class Live {
  static const _ch = MethodChannel('koridor/live');

  static const green = 0xFF2E7D32;
  static const orange = 0xFFEF6C00;
  static const red = 0xFFC62828;

  static DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  static String _lastKey = '';
  static int _lastColor = 0;
  static bool _shown = false;

  /// Takip durumunu bildirime yansıtır. Tracker her değiştiğinde çağrılır;
  /// içerik değişmedikçe ya da 1 sn dolmadıkça yeniden göndermez.
  static void sync(Tracker t) {
    final r = t.primary;
    if (r == null) {
      if (_shown) {
        _shown = false;
        _lastKey = '';
        _lastColor = 0;
        _invoke('clear');
      }
      return;
    }
    final now = DateTime.now();
    final c = r.corridor;
    final avg = r.avgKmh(now);
    final allowed = r.allowedKmh(now);
    final over = avg > c.limitKmh;
    final near = !over && avg > c.limitKmh - 3;
    final color = over ? red : (near ? orange : green);
    final km = (r.remainingM / 1000).toStringAsFixed(1);
    final max = allowedText(allowed);
    final text = over
        ? 'Limit aşıldı! Sona kadar en fazla $max • kalan $km km'
        : 'Ort. ${avg.round()} / ${c.limitKmh} • en fazla $max • kalan $km km';
    final chip = '${avg.round()}';
    final key = '$chip|$color|$max|$km';
    if (key == _lastKey && now.difference(_last) < const Duration(seconds: 5)) return;
    // Renk değişimi hemen, diğerleri en fazla saniyede bir.
    if (color == _lastColor && now.difference(_last) < const Duration(seconds: 1)) return;
    _last = now;
    _lastColor = color;
    _lastKey = key;
    _shown = true;
    _invoke('update', {
      'title': '${c.name} • limit ${c.limitKmh}',
      'text': text,
      'chip': chip,
      'color': color,
      'progress': (r.progress * 1000).round(),
    });
  }

  /// "En fazla" hızın metni: 0 ise artık limit altına inilemez.
  static String allowedText(double allowed) {
    if (allowed >= 999) return '—';
    if (allowed <= 0) return 'yok';
    return '${allowed.round()} km/s';
  }

  static Future<void> requestPermission() => _invoke('requestPermission');

  /// Android 16+: durum çubuğu çipine izin var mı (null: desteklenmiyor/bilinmiyor).
  static Future<bool?> canPromote() async {
    try {
      return await _ch.invokeMethod<bool>('canPromote');
    } catch (_) {
      return null;
    }
  }

  static Future<void> openSettings() => _invoke('openSettings');

  static Future<void> _invoke(String m, [Object? args]) async {
    try {
      await _ch.invokeMethod(m, args);
    } catch (_) {}
  }
}
