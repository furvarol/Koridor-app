package com.furkanvarol.koridor

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle

/// Koridor içindeyken süren bildirim. Android 16+ cihazlarda "Live Update"
/// olarak yükseltilmesi istenir: durum çubuğunda (saatin yanında) ortalama
/// hızı gösteren bir çip çıkar. Eski sürümlerde normal kalıcı bildirimdir.
///
/// Android 16 API'leri (setRequestPromotedOngoing, setShortCriticalText)
/// doğrudan çağrılmaz; platformun okuduğu extras anahtarları kullanılır.
class LiveNotifier(private val activity: Activity) {
    companion object {
        private const val CHANNEL_ID = "koridor_live"
        private const val NOTIF_ID = 4242
        private const val EXTRA_REQUEST_PROMOTED_ONGOING = "android.requestPromotedOngoing"
        private const val EXTRA_SHORT_CRITICAL_TEXT = "android.shortCriticalText"
        private const val POST_NOTIFICATIONS = "android.permission.POST_NOTIFICATIONS"
    }

    private val nm = activity.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    /// Android 13+ bildirim iznini ister (verilmemişse).
    fun requestPermission() {
        if (Build.VERSION.SDK_INT >= 33 &&
            activity.checkSelfPermission(POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            activity.requestPermissions(arrayOf(POST_NOTIFICATIONS), 7301)
        }
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val ch = NotificationChannel(
            CHANNEL_ID, "Koridor canlı durum", NotificationManager.IMPORTANCE_DEFAULT
        )
        ch.description = "Koridor içindeyken ortalama hız ve kalan yol"
        ch.setSound(null, null)
        ch.enableVibration(false)
        ch.setShowBadge(false)
        nm.createNotificationChannel(ch)
    }

    fun update(title: String, text: String, chip: String, color: Int, progress: Int) {
        ensureChannel()
        val intent = Intent(activity, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val pi = PendingIntent.getActivity(
            activity, 0, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val b = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(activity, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(activity)
        }
        b.setSmallIcon(R.drawable.ic_stat_koridor)
            .setContentTitle(title)
            .setContentText(text)
            .setColor(color)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setContentIntent(pi)
            .setCategory("navigation")
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setProgress(1000, progress.coerceIn(0, 1000), false)
        val extras = Bundle()
        extras.putBoolean(EXTRA_REQUEST_PROMOTED_ONGOING, true)
        extras.putCharSequence(EXTRA_SHORT_CRITICAL_TEXT, chip)
        b.addExtras(extras)
        try {
            nm.notify(NOTIF_ID, b.build())
        } catch (e: SecurityException) {
            // Bildirim izni yok.
        }
    }

    fun clear() = nm.cancel(NOTIF_ID)

    /// Android 16+: uygulamanın Live Update göstermesine izin var mı (null: bilinmiyor).
    fun canPromote(): Boolean? {
        if (Build.VERSION.SDK_INT < 36) return null
        return try {
            nm.javaClass.getMethod("canPostPromotedNotifications").invoke(nm) as? Boolean
        } catch (e: Exception) {
            null
        }
    }

    /// Canlı bildirim (Live Update) ayarını, yoksa uygulamanın bildirim ayarını açar.
    fun openSettings(): Boolean {
        val pkg = activity.packageName
        val candidates = listOf(
            Intent("android.settings.APP_NOTIFICATION_PROMOTION_SETTINGS")
                .putExtra("android.provider.extra.APP_PACKAGE", pkg),
            Intent("android.settings.APP_NOTIFICATION_SETTINGS")
                .putExtra("android.provider.extra.APP_PACKAGE", pkg),
        )
        for (i in candidates) {
            try {
                activity.startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return true
            } catch (e: Exception) {
                // sıradakini dene
            }
        }
        return false
    }
}
