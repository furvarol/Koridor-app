import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android resim içinde resim (PiP) köprüsü. Yerel taraf: MainActivity.kt.
class Pip {
  static const _ch = MethodChannel('koridor/pip');

  /// Uygulama şu an PiP penceresinde mi.
  static final ValueNotifier<bool> active = ValueNotifier(false);

  static bool _autoEnter = false;

  static void init() {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'pipChanged') active.value = call.arguments == true;
    });
  }

  /// Açıkken uygulamadan çıkınca (ana ekran/geri hareketi) otomatik PiP'e geçer.
  static Future<void> setAutoEnter(bool enabled) async {
    if (_autoEnter == enabled) return;
    _autoEnter = enabled;
    try {
      await _ch.invokeMethod('setAutoEnter', enabled);
    } on PlatformException catch (_) {
    } on MissingPluginException catch (_) {}
  }

  /// PiP'e hemen geçer; desteklenmiyorsa false döner.
  static Future<bool> enter() async {
    try {
      return await _ch.invokeMethod<bool>('enter') ?? false;
    } on PlatformException catch (_) {
      return false;
    } on MissingPluginException catch (_) {
      return false;
    }
  }
}
