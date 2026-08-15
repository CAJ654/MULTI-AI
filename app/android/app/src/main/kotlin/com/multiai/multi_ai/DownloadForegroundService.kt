package com.multiai.multi_ai

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Persistent low-priority notification while an on-device model download is
 * in flight, so Android treats the app as foreground and doesn't suspend the
 * process (and the download with it) a short time after it's backgrounded —
 * Home button, screen off, switching apps. Started/stopped from
 * ModelPool.ensureOnDeviceDownload via MainActivity's "multiai/device"
 * channel — see download_foreground_service.dart.
 *
 * Deliberately narrow in scope: the manifest doesn't set
 * android:stopWithTask="false", so swiping the app away from Recents still
 * stops the download like it always did. Only Home/screen-off/app-switch are
 * covered — the common "I background the app, not kill it" case.
 */
class DownloadForegroundService : Service() {
    companion object {
        private const val CHANNEL_ID = "model_downloads"
        private const val NOTIFICATION_ID = 1
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, buildNotification())
        // Not sticky: if the OS kills the whole process under memory
        // pressure, there's no download left to resume this service for —
        // an orphaned notification with nothing behind it would be worse
        // than none.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        super.onDestroy()
    }

    private fun buildNotification(): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Model downloads",
                NotificationManager.IMPORTANCE_LOW,
            )
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Multi-AI")
            .setContentText("Downloading a model…")
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }
}
