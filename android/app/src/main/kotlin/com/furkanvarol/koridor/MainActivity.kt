package com.furkanvarol.koridor

import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Resim içinde resim (PiP): takip açıkken uygulamadan çıkınca hız küçük
/// pencerede görünmeye devam eder. Flutter tarafı "koridor/pip" kanalını kullanır.
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var autoEnter = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "koridor/pip").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "setAutoEnter" -> {
                        autoEnter = call.arguments as? Boolean ?: false
                        updateParams()
                        result.success(null)
                    }
                    "enter" -> result.success(enterPip())
                    "isSupported" -> result.success(isPipSupported())
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun isPipSupported(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature("android.software.picture_in_picture")

    private fun buildParams(): PictureInPictureParams? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return null
        val b = PictureInPictureParams.Builder().setAspectRatio(Rational(1, 1))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            b.setAutoEnterEnabled(autoEnter)
            b.setSeamlessResizeEnabled(false)
        }
        return b.build()
    }

    private fun updateParams() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || !isPipSupported()) return
        val p = buildParams() ?: return
        setPictureInPictureParams(p)
    }

    private fun enterPip(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || !isPipSupported()) return false
        val p = buildParams() ?: return false
        return try {
            enterPictureInPictureMode(p)
        } catch (e: IllegalStateException) {
            false
        }
    }

    // Android 12 öncesinde otomatik giriş yok; ana ekrana basınca elle gir.
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (autoEnter && Build.VERSION.SDK_INT < Build.VERSION_CODES.S) enterPip()
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        channel?.invokeMethod("pipChanged", isInPictureInPictureMode)
    }
}
