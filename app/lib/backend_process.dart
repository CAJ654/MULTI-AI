// Locating, provisioning, starting and stopping the Python backend that ships
// inside the packaged Windows build.
//
// In development you start the backend yourself (`multi-ai-server`) and this
// file stays out of the way: with no `backend/` directory next to the
// executable, [BackendRuntime.isBundled] is false and the app just talks to
// whatever is already on port 8000, exactly as it always has.
//
// In a packaged build the app owns the backend's whole lifecycle, because a
// downloader has no venv, no `pip install -e .`, and no reason to know a Python
// server exists. Three facts shape how that works:
//
//  1. The interpreter is CPython's *embeddable* distribution. It ignores
//     PYTHONPATH (see installer/runtime/bootstrap.py), so paths are handed
//     over in MULTI_AI_PATH and assembled after startup instead.
//  2. The heavy dependencies are not in the installer. torch alone is 4.12GB
//     and GitHub Releases caps a file at 2GB, so they are pip-installed on
//     first launch — see [provision].
//  3. They install under %LOCALAPPDATA%, not next to the app. Program Files is
//     not user-writable, and requiring admin rights for a first launch that
//     already takes ten minutes is a bad trade.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Where the packaged interpreter, the compiled backend, and the
/// pip-installed dependencies live on disk.
class BackendRuntime {
  /// Directory holding the running executable — the install root in a
  /// packaged build, `build/windows/.../Release` under `flutter run`.
  static Directory get appDir =>
      File(Platform.resolvedExecutable).parent;

  /// Payload staged by the installer: `python/`, `multi_ai/`, `bootstrap.py`,
  /// `pip.pyz`, `requirements.txt`.
  static Directory get backendDir => Directory('${appDir.path}\\backend');

  /// True when running from a packaged build, i.e. when there is a backend to
  /// supervise. False under `flutter run`, where the developer runs their own.
  static bool get isBundled =>
      Platform.isWindows && File('${backendDir.path}\\bootstrap.py').existsSync();

  static File get pythonExe => File('${backendDir.path}\\python\\python.exe');
  static File get pipPyz => File('${backendDir.path}\\pip.pyz');
  static File get bootstrap => File('${backendDir.path}\\bootstrap.py');
  static File get requirements => File('${backendDir.path}\\requirements.txt');

  /// User-writable state: the pip-installed dependencies and the marker
  /// recording which requirements they satisfy.
  ///
  /// Deliberately *not* `%LOCALAPPDATA%\MultiAI`. That is Velopack's install
  /// root — it derives it as `%LOCALAPPDATA%\<packId>`, and the packId is
  /// `MultiAI` (see .github/workflows/release.yml) — so it holds `current\`,
  /// `packages\` and `Update.exe`, and Velopack rewrites it on every update.
  /// Putting a 2.5GB dependency tree inside a directory the updater manages is
  /// asking for it to be cleaned up mid-update. The `-Runtime` suffix keeps it
  /// adjacent and obvious without being inside.
  static Directory get userDir {
    final local = Platform.environment['LOCALAPPDATA'] ??
        '${Platform.environment['USERPROFILE']}\\AppData\\Local';
    return Directory('$local\\MultiAI-Runtime');
  }

  static Directory get sitePackages =>
      Directory('${userDir.path}\\site-packages');

  static File get _marker => File('${userDir.path}\\.provisioned');

  /// The dependency list these packages were installed from. Copied into the
  /// marker on success and compared on every launch, so shipping an update
  /// that edits requirements.txt re-provisions rather than running against
  /// stale packages. Stored verbatim rather than hashed — the file is a few
  /// hundred bytes, and a mismatch is then readable in a bug report.
  static String get _requirementsText => requirements.readAsStringSync();

  /// Whether the dependencies for *this* build's requirements are installed.
  static bool get isProvisioned {
    if (!isBundled) return true; // dev machine: not ours to judge
    if (!_marker.existsSync()) return false;
    try {
      return _marker.readAsStringSync() == _requirementsText;
    } on FileSystemException {
      return false;
    }
  }

  static void _markProvisioned() {
    userDir.createSync(recursive: true);
    _marker.writeAsStringSync(_requirementsText);
  }

  /// Opt-out marker for [removeRuntimeOnUninstall].
  ///
  /// Kept inside [userDir] rather than with the app's other settings because
  /// it is a property of the runtime, not of the user: if the runtime is gone
  /// the question is moot, and deleting the runtime takes the preference with
  /// it, so a later reinstall starts from the default again.
  static File get _keepMarker => File('${userDir.path}\\.keep-on-uninstall');

  /// Whether the ~2.5GB dependency stack should survive uninstalling the app.
  /// False by default — uninstalling removes what the app downloaded, and
  /// anyone who plans to reinstall can opt out first to keep the reinstall
  /// instant. Surfaced in [StorageSettingsDialog].
  static bool get keepsRuntimeOnUninstall => _keepMarker.existsSync();

  static void setKeepRuntimeOnUninstall(bool keep) {
    if (keep) {
      userDir.createSync(recursive: true);
      _keepMarker.writeAsStringSync(
        'Multi-AI keeps this directory when the app is uninstalled.\n'
        'Delete this file to have uninstall remove it instead.\n',
      );
    } else if (_keepMarker.existsSync()) {
      _keepMarker.deleteSync();
    }
  }

  /// Removes the dependency stack, unless [keepsRuntimeOnUninstall].
  ///
  /// Called from the `--veloapp-uninstall` hook. Velopack deletes its own
  /// install root and nothing else, so without this the 2.5GB outlives an
  /// uninstall with nothing to indicate it is still there.
  ///
  /// Two details exist to fit the hook's 30-second budget, which a recursive
  /// delete of tens of thousands of small files can easily blow:
  ///
  ///  1. The provisioned marker goes first, synchronously. It is one small
  ///     file, so it always completes — and it means an interrupted delete
  ///     leaves the runtime unambiguously *un*provisioned rather than looking
  ///     complete while half its packages are missing.
  ///  2. The bulk delete is handed to a detached `rmdir`, which outlives this
  ///     process and so is not subject to the timeout at all. It runs from
  ///     system32, not from the directory being removed, so nothing it needs
  ///     disappears underneath it.
  static void removeRuntimeOnUninstall() {
    try {
      if (!userDir.existsSync() || keepsRuntimeOnUninstall) return;
      if (_marker.existsSync()) _marker.deleteSync();
      Process.start(
        'cmd.exe',
        ['/c', 'rmdir', '/s', '/q', userDir.path],
        mode: ProcessStartMode.detached,
        runInShell: false,
      );
    } catch (_) {
      // Best-effort cleanup during an uninstall that is happening regardless.
      // Failing loudly here would only produce an error nobody can act on.
    }
  }

  /// Environment for a spawned backend process. MULTI_AI_PATH carries what
  /// PYTHONPATH cannot (see the ._pth note above): the compiled `multi_ai`
  /// package, then the provisioned dependencies.
  static Map<String, String> get _env => {
        'MULTI_AI_PATH': '${backendDir.path};${sitePackages.path}',
        'MULTI_AI_PORT': '$port',
      };

  static const int port = 8000;
}

/// A line of output from provisioning, for the setup screen to display.
class ProvisionProgress {
  const ProvisionProgress(this.line, {this.isError = false});
  final String line;
  final bool isError;
}

/// Downloads and installs the chat-time dependencies into
/// [BackendRuntime.sitePackages]. Emits pip's output line by line; completes
/// when pip exits, throwing on a non-zero exit code.
///
/// This is the ~2.5GB first-run download. It is resumable only in the sense
/// that pip caches wheels — an interrupted run re-runs from the start but
/// usually re-uses what it already fetched.
Stream<ProvisionProgress> provision() async* {
  final controller = StreamController<ProvisionProgress>();

  BackendRuntime.sitePackages.createSync(recursive: true);

  final process = await Process.start(
    BackendRuntime.pythonExe.path,
    [
      BackendRuntime.pipPyz.path,
      'install',
      '--target', BackendRuntime.sitePackages.path,
      '--requirement', BackendRuntime.requirements.path,
      // Required, not an optimisation. With `--target`, pip refuses to touch a
      // package directory that already exists unless `--upgrade` is given — it
      // logs "Specify --upgrade to force replacement" and skips it, then exits
      // 0. On a fresh machine that never happens, but it is exactly the case
      // on an app update whose requirements.txt changed: without this the old
      // packages survive, pip reports success, and [_markProvisioned] records
      // the new requirements against dependencies that never moved.
      '--upgrade',
      // torch resolves from PyTorch's own index (the PyPI Windows wheel is
      // CPU-only, which would make every server model unusably slow); the
      // rest fall through to PyPI.
      '--index-url', 'https://download.pytorch.org/whl/cu128',
      '--extra-index-url', 'https://pypi.org/simple',
      '--no-warn-script-location',
      // Progress bars are redrawn with carriage returns, which arrive here as
      // one enormous line rather than as animation.
      '--progress-bar', 'off',
    ],
    workingDirectory: BackendRuntime.backendDir.path,
  );

  process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((l) => controller.add(ProvisionProgress(l)));
  process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((l) => controller.add(ProvisionProgress(l, isError: true)));

  unawaited(process.exitCode.then((code) {
    if (code == 0) {
      BackendRuntime._markProvisioned();
      controller.close();
    } else {
      controller.addError(
        Exception('Dependency install failed (pip exited $code). '
            'Check your internet connection and try again.'),
      );
      controller.close();
    }
  }));

  yield* controller.stream;
}

/// Owns the backend child process for the lifetime of the app.
class BackendSupervisor {
  Process? _process;

  /// True once the backend answers a request, whether we started it or not.
  bool get isRunning => _process != null;

  /// Whether *something* is already serving on the backend port. Checked
  /// before spawning so a developer's hand-started server, or an orphan left
  /// by a previous crash, is adopted rather than fought over — two processes
  /// racing for port 8000 produces a confusing "address in use" crash loop.
  static Future<bool> ping({Duration timeout = const Duration(seconds: 1)}) async {
    try {
      final response = await http
          .get(Uri.parse('http://localhost:${BackendRuntime.port}/api/hello'))
          .timeout(timeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Starts the bundled backend and waits for it to answer. No-op when
  /// something is already serving, or when there is no bundled backend to
  /// start (development).
  ///
  /// Throws [TimeoutException] if the process starts but never becomes
  /// healthy, and [ProcessException] if it cannot be launched at all.
  Future<void> start({Duration timeout = const Duration(seconds: 60)}) async {
    if (await ping()) return;
    if (!BackendRuntime.isBundled) return;

    _process = await Process.start(
      BackendRuntime.pythonExe.path,
      [BackendRuntime.bootstrap.path],
      workingDirectory: BackendRuntime.backendDir.path,
      environment: BackendRuntime._env,
    );

    // Drained rather than ignored: an unread pipe fills its buffer and blocks
    // the child mid-write, which looks exactly like a hang.
    final log = StringBuffer();
    _process!.stdout.transform(utf8.decoder).listen(log.write);
    _process!.stderr.transform(utf8.decoder).listen(log.write);

    var exited = false;
    unawaited(_process!.exitCode.then((_) => exited = true));

    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (exited) {
        throw Exception('The backend exited during startup.\n\n$log');
      }
      if (await ping()) return;
      await Future.delayed(const Duration(milliseconds: 400));
    }
    await stop();
    throw TimeoutException(
      'The backend did not respond within ${timeout.inSeconds}s.\n\n$log',
    );
  }

  /// Stops the backend if we started it. Left alone otherwise — killing a
  /// server the developer started by hand would be rude.
  Future<void> stop() async {
    final process = _process;
    _process = null;
    if (process == null) return;
    process.kill();
    await process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
  }
}
