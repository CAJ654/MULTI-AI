// Checking for a new Android release and pointing the user at it.
//
// Android ships as a signed APK attached to a GitHub release, not through the
// Play Store (see the README's "Shipping an Android release" section). That
// keeps the $25 developer fee, the review wait, and the Data Safety form out
// of this project, at the cost of no store listing to push updates through.
// `velopack_flutter` (update_service.dart) no-ops on Android, so without this
// a user has to remember to revisit the releases page.
//
// This deliberately does not download or install anything itself — that
// would need a FileProvider, the REQUEST_INSTALL_PACKAGES permission, and
// native code to fire an install intent. Instead it finds the release and
// hands the user to the browser via url_launcher (already a dependency),
// which downloads the APK and runs Android's normal unknown-sources install
// flow — the same manual mechanics the README already describes, just
// reached automatically instead of by the user remembering to check.
//
// Same "nothing here nags" posture as UpdateService: the check runs
// unprompted in the background, a failure is swallowed, and the only thing a
// user ever sees is a dismissible banner once a genuinely newer release
// exists (see app_shell.dart).

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'chat_store.dart' show appDataFile;
import 'model_pool.dart' show isAndroidPlatform;

/// One GitHub release's Android asset, resolved from the API response.
class AndroidUpdateInfo {
  const AndroidUpdateInfo({required this.version, required this.downloadUrl});

  /// The release tag with its leading "v" stripped, e.g. "1.1.1".
  final String version;

  /// The APK asset's direct download URL.
  final String downloadUrl;
}

/// Owns the Android update check for the lifetime of the app. A singleton for
/// the same reason as UpdateService: StartupGate starts the check, and
/// AppShell — built later, and rebuilt often — reads the result.
class AndroidUpdateChecker {
  AndroidUpdateChecker._();

  static final AndroidUpdateChecker instance = AndroidUpdateChecker._();

  /// GitHub's "latest" alias resolves to the most recent *published,
  /// non-prerelease* release — a draft from an in-progress workflow run is
  /// invisible here, so nothing can point a user at a build nobody has
  /// reviewed yet.
  static const String _latestReleaseUrl =
      'https://api.github.com/repos/CAJ654/MULTI-AI/releases/latest';

  final _controller = StreamController<AndroidUpdateInfo?>.broadcast();

  /// Emits the available update, or null once there's nothing to show
  /// (already current, or the user dismissed this version).
  Stream<AndroidUpdateInfo?> get onChange => _controller.stream;

  AndroidUpdateInfo? _available;
  AndroidUpdateInfo? get available => _available;

  bool _checking = false;

  void _set(AndroidUpdateInfo? next) {
    _available = next;
    _controller.add(next);
  }

  /// Checks for a newer release. Fire-and-forget: callers do not await this,
  /// same as UpdateService.checkNow() — it makes a network call that should
  /// never sit between launch and a usable app.
  void checkNow() {
    if (!isAndroidPlatform || _checking) return;
    _checking = true;
    unawaited(_run().whenComplete(() => _checking = false));
  }

  Future<void> _run() async {
    try {
      final response = await http
          .get(Uri.parse(_latestReleaseUrl), headers: {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final tag = json['tag_name'] as String?;
      if (tag == null) return;
      final latestVersion = tag.startsWith('v') ? tag.substring(1) : tag;

      final assets = json['assets'] as List<dynamic>? ?? const [];
      final apkAsset = assets.cast<Map<String, dynamic>>().firstWhere(
            (a) => (a['name'] as String? ?? '').endsWith('-android.apk'),
            orElse: () => const {},
          );
      final downloadUrl = apkAsset['browser_download_url'] as String?;
      if (downloadUrl == null) return;

      final info = PackageInfo.fromPlatform();
      final currentVersion = (await info).version;
      if (!_isNewer(latestVersion, currentVersion)) {
        _set(null);
        return;
      }

      if (await _dismissedVersion() == latestVersion) {
        _set(null);
        return;
      }

      _set(AndroidUpdateInfo(version: latestVersion, downloadUrl: downloadUrl));
    } catch (_) {
      // Offline, rate-limited, or a malformed response - the app works fine
      // on the version already installed, so this is not worth surfacing.
    }
  }

  /// Records that the user dismissed [version], so it doesn't reappear until
  /// a newer one is published.
  Future<void> dismiss(String version) async {
    _set(null);
    try {
      final file = await appDataFile('android_update_dismissed.json');
      await file.writeAsString(jsonEncode({'dismissedVersion': version}));
    } catch (_) {
      // Best-effort: worst case the banner reappears next launch.
    }
  }

  Future<String?> _dismissedVersion() async {
    try {
      final file = await appDataFile('android_update_dismissed.json');
      if (!await file.exists()) return null;
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return data['dismissedVersion'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Plain dotted-integer comparison (e.g. "1.1.1" vs "1.0.2+3" - the build
  /// number after '+' is ignored, matching pubspec.yaml's version scheme).
  bool _isNewer(String latest, String current) {
    List<int> parts(String v) =>
        v.split('+').first.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final a = parts(latest), b = parts(current);
    for (var i = 0; i < a.length || i < b.length; i++) {
      final av = i < a.length ? a[i] : 0;
      final bv = i < b.length ? b[i] : 0;
      if (av != bv) return av > bv;
    }
    return false;
  }
}
