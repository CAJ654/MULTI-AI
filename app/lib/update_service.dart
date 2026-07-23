// Checking for, downloading and applying updates to the app itself.
//
// Releases are Velopack packages published as GitHub release assets. Velopack
// diffs each release against the one before it, so a user moving from the
// previous version downloads a delta — a few MB — rather than the whole ~200MB
// app. See .github/workflows/release.yml for the packaging side.
//
// The shape here deliberately matches provision() in backend_process.dart: a
// plain object exposing a stream of progress events, with the widget layer
// subscribing and calling setState. No state-management package is involved
// anywhere in this app.
//
// Nothing here nags. The check runs unprompted in the background and a failure
// is swallowed — the app works perfectly well on the version already
// installed, so an unreachable update feed is not worth an error dialog. The
// only thing a user ever sees is a "Relaunch to Update" banner, once a new
// version is downloaded and ready to apply (see chat_screen.dart), and
// applying it is always their click.

import 'dart:async';

import 'package:velopack_flutter/velopack_flutter.dart';

/// Where the app is in the check → download → ready sequence.
enum UpdateState {
  /// No check has run, or the last one found nothing.
  idle,
  checking,
  downloading,

  /// A new version is on disk and will be applied on the next relaunch.
  ready,

  /// The check or download failed. Deliberately invisible to the user.
  error,
}

class UpdateStatus {
  const UpdateStatus(
    this.state, {
    this.version,
    this.percent = 0,
    this.message,
  });

  final UpdateState state;

  /// The version being moved to. Null until the check has found one.
  final String? version;

  /// Download progress, 0-100. See the note in [UpdateService._run] about why
  /// this is not usable for a live progress bar.
  final int percent;

  /// Failure detail. For logs and bug reports, not for the UI.
  final String? message;
}

/// Owns the update check for the lifetime of the app. A singleton because the
/// check is per-process, not per-screen: [StartupGate] starts it and
/// [ChatScreen] — built later, and rebuilt often — reads the result.
class UpdateService {
  UpdateService._();

  static final UpdateService instance = UpdateService._();

  /// Base URL Velopack reads the release feed from.
  ///
  /// GitHub's `/releases/latest/download/` path serves a named asset from the
  /// most recent *published, non-prerelease* release, which is exactly the
  /// gate this project already wants: the release workflow publishes drafts,
  /// a draft is invisible to this URL, so no installed app can update itself
  /// to a build nobody has reviewed yet. Publishing the draft is what ships it.
  ///
  /// It must be an http(s) URL. velopack_flutter builds a Velopack
  /// `HttpSource` from this string and nothing else — it does not sniff the
  /// string for a GitHub repo or a local path, so neither a plain repo URL nor
  /// a directory path works here. To test against a local pack output, serve
  /// it and point a build at it:
  ///
  ///   python -m http.server 8080 --directory Releases
  ///   flutter build windows --release \
  ///     --dart-define=MULTI_AI_UPDATE_FEED=http://localhost:8080/
  static const String feedUrl = String.fromEnvironment(
    'MULTI_AI_UPDATE_FEED',
    defaultValue: 'https://github.com/CAJ654/MULTI-AI/releases/latest/download/',
  );

  final _controller = StreamController<UpdateStatus>.broadcast();

  /// Emits on every state change. Broadcast rather than single-subscription:
  /// the chat screen attaches and detaches on its own lifecycle and may do so
  /// more than once, which a single-subscription stream would reject.
  Stream<UpdateStatus> get onChange => _controller.stream;

  UpdateStatus _status = const UpdateStatus(UpdateState.idle);

  /// The current status, for a listener that attaches after a change was
  /// already emitted — a broadcast stream does not replay.
  UpdateStatus get status => _status;

  void _set(UpdateStatus next) {
    _status = next;
    _controller.add(next);
  }

  /// Checks for an update and downloads it if there is one. Fire-and-forget:
  /// callers do not await this, and must not — it makes network calls and, on
  /// a real update, downloads a package, none of which should sit between
  /// launch and the app being usable.
  void checkNow() {
    // Re-entrant calls are ignored. `error` is retryable, `idle` covers "the
    // last check found nothing"; the other three mean one is already in
    // flight or has already succeeded.
    if (_status.state != UpdateState.idle && _status.state != UpdateState.error) {
      return;
    }
    unawaited(_run());
  }

  Future<void> _run() async {
    _set(const UpdateStatus(UpdateState.checking));
    try {
      // getLatestUpdateInfo rather than isUpdateAvailable: same one network
      // round trip, but it also carries the version string the banner shows.
      final info = await getLatestUpdateInfo();
      if (info == null) {
        _set(const UpdateStatus(UpdateState.idle)); // already current
        return;
      }

      final version = info.targetFullRelease.version;
      _set(UpdateStatus(UpdateState.downloading, version: version));

      // The stream closing is what signals the download finished; the progress
      // values are not usable for a live bar. velopack_flutter collects them
      // through an mpsc channel that it only begins draining *after* its
      // blocking download call has already returned, so the whole sequence
      // arrives in one burst at the end. Harmless here — nothing renders a
      // progress bar — but it is why nothing should.
      await for (final percent in checkAndDownloadUpdatesWithProgress()) {
        _set(UpdateStatus(
          UpdateState.downloading,
          version: version,
          percent: percent,
        ));
      }

      _set(UpdateStatus(UpdateState.ready, version: version, percent: 100));
    } catch (e) {
      // Thrown on any build Velopack did not install — `flutter run`, or an
      // unzipped portable build — because the update manager has no app
      // manifest to read. Also covers simply being offline. Either way the
      // right response is to carry on with the version already running.
      _set(UpdateStatus(UpdateState.error, message: '$e'));
    }
  }

  /// Applies the downloaded update and relaunches into it.
  ///
  /// On success this does not return: Velopack's updater replaces the app
  /// files and starts the new version as a fresh process. The backend child
  /// process dies with this one, which is what we want — the new version
  /// starts its own.
  Future<void> applyAndRestart() => updateAndRestart();
}
