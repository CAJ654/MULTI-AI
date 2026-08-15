// Keeps an on-device model download alive when the app is backgrounded on
// Android (Home button, screen off, switching apps) rather than swiped away
// from Recents. Without this, Android can suspend the process a short time
// after the app leaves the foreground, silently stalling a multi-gigabyte
// fetch — see model_pool.dart's ensureOnDeviceDownload, which calls start()
// on the first download to begin and stop() once the last one finishes.
//
// A hand-rolled platform channel rather than a plugin (e.g.
// flutter_foreground_task): MainActivity.kt already needs edits for
// device_ram.dart's RAM read, so the marginal cost of a second method on the
// same channel is small next to a whole plugin's task-handler machinery for
// what's just "show one persistent low-priority notification". No-op on
// every platform except Android — desktop doesn't need this (minimizing a
// window doesn't suspend the process the way Android backgrounding does),
// and no other platform declares the manifest permissions this needs.
//
// Deliberately narrow in scope: the service does not set
// android:stopWithTask="false", so swiping the app away from Recents stops
// the download like it always did — only Home/screen-off/app-switch are
// covered. It also only wraps downloads started from the model detail page
// (ModelPool.ensureOnDeviceDownload), not the implicit first-chat download
// llamadart can trigger on its own (that path has no progress/cancel UI at
// all yet — a separate, pre-existing gap).
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

// Not model_pool.dart's isAndroidPlatform: that file imports this one (to
// call start()/stop()), and importing back would make the two files
// circular. Same check, duplicated rather than shared — see
// platform_check.dart's header comment for why isAndroidHost (not
// defaultTargetPlatform) is the right primitive here.
import 'platform_check.dart';

class DownloadForegroundService {
  DownloadForegroundService._();

  static const MethodChannel _channel = MethodChannel('multiai/device');

  static bool get _isAndroid => !kIsWeb && isAndroidHost;

  /// Starts the persistent "downloading a model" notification. Safe to call
  /// even if it's already showing.
  static Future<void> start() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('startDownloadService');
    } on PlatformException {
      // Best-effort: a failed notification/service start shouldn't block or
      // fail the download itself, only the OS's willingness to let it run
      // fully backgrounded.
    }
  }

  /// Stops the notification. Safe to call even if none is showing.
  static Future<void> stop() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stopDownloadService');
    } on PlatformException {
      // See start() — best-effort.
    }
  }
}
