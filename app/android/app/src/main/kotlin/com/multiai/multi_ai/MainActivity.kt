package com.multiai.multi_ai

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Only extra wiring beyond the default Flutter template: one MethodChannel
 * ("multiai/device") backing device_ram_io.dart's Android RAM read (there's
 * no dart:ffi equivalent reachable from Dart for this) and
 * download_foreground_service.dart's download-notification start/stop. No
 * plugin exists for either on this project — both are small enough that
 * hand-rolling one channel is less new surface than pulling one in.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "multiai/device"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "totalRamBytes" -> result.success(totalRamBytes())
                    "startDownloadService" -> {
                        ContextCompat.startForegroundService(
                            this,
                            Intent(this, DownloadForegroundService::class.java),
                        )
                        result.success(null)
                    }
                    "stopDownloadService" -> {
                        stopService(Intent(this, DownloadForegroundService::class.java))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun totalRamBytes(): Long {
        val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val info = ActivityManager.MemoryInfo()
        manager.getMemoryInfo(info)
        return info.totalMem
    }
}
