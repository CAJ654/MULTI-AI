import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

import '../../backend_process.dart' show BackendRuntime, ProvisionProgress;
import 'component.dart';

/// Where one component's files live on disk, and how they get there.
///
/// Mirrors [BackendRuntime] (`backend_process.dart`) closely, but scoped per
/// component and isolated from the main backend's own site-packages: a
/// component's dependencies (Flask, lxml, ...) must never share `sys.path`
/// with the main backend's (torch, transformers, ...) — two independently
/// versioned dependency trees nothing here has checked against each other.
///
/// Reuses [BackendRuntime.pythonExe]/[BackendRuntime.pipPyz] rather than
/// bundling a second interpreter — see [available].
class ComponentRuntime {
  ComponentRuntime(this.component);

  final LocalComponent component;

  /// True only in a packaged Windows build with a bundled backend whose
  /// interpreter components can borrow — see [BackendRuntime.isBundled].
  /// False under `flutter run` and on Android, where there is nothing to
  /// install into.
  static bool get available => BackendRuntime.isBundled;

  static Directory get _componentsRoot =>
      Directory('${BackendRuntime.userDir.path}\\components');

  /// This component's own directory: its dependencies, its generated config
  /// (SearXNG's `settings.yml`), and its install marker. A sibling of
  /// [BackendRuntime.sitePackages], never inside it.
  Directory get baseDir => Directory('${_componentsRoot.path}\\${component.id}');

  Directory get sitePackages => Directory('${baseDir.path}\\site-packages');

  File get _marker => File('${baseDir.path}\\.installed');
  File get _requirementsFile => File('${baseDir.path}\\requirements.txt');

  /// Whether this component's dependencies are on disk.
  ///
  /// A plain marker-file check — unlike [BackendRuntime.isProvisioned] this
  /// doesn't compare against the requirements text, because that text lives
  /// in a Flutter asset ([rootBundle]), which only loads asynchronously.
  /// Picking up a requirements change is a manual "delete & reinstall" from
  /// the Add-ons tab instead, which is the right cost for a component whose
  /// dependencies change far less often than the main backend's do.
  bool get isInstalled => _marker.existsSync();

  Future<void> _writeAssetFile(String assetPath, File destination) async {
    final text = await rootBundle.loadString(assetPath);
    await destination.parent.create(recursive: true);
    await destination.writeAsString(text);
  }

  /// Materializes a bundled asset (a bootstrap script, a settings template)
  /// into this component's own directory, so a spawned Python process — which
  /// needs a real file path, not an asset bundle entry — can read it.
  /// Overwrites unconditionally: these are small, static, and cheap to
  /// re-write on every start rather than tracked for staleness.
  Future<File> materializeAsset(String assetFileName, {String? into}) async {
    final destination = File('${baseDir.path}\\${into ?? assetFileName}');
    await _writeAssetFile('assets/components/$assetFileName', destination);
    return destination;
  }

  /// Downloads and installs this component into [sitePackages]. Emits pip's
  /// output line by line and completes when it exits, throwing on a non-zero
  /// exit code — the same streaming shape as [BackendRuntime]'s own
  /// top-level `provision()`, which this deliberately mirrors rather than
  /// shares: that one targets the main backend's CUDA-specific index URL,
  /// this one doesn't need it, and duplicating a ~30 line function reads
  /// clearer than threading a flag through a shared one for a single
  /// difference.
  Stream<ProvisionProgress> provision() async* {
    if (!available) {
      yield const ProvisionProgress(
        'This build has no bundled Python runtime to install into.',
        isError: true,
      );
      return;
    }

    final controller = StreamController<ProvisionProgress>();

    await sitePackages.create(recursive: true);
    await _writeAssetFile(
      'assets/components/${component.id}_requirements.txt',
      _requirementsFile,
    );

    final process = await Process.start(
      BackendRuntime.pythonExe.path,
      [
        BackendRuntime.pipPyz.path,
        'install',
        '--target', sitePackages.path,
        '--requirement', _requirementsFile.path,
        // See BackendRuntime.provision()'s doc comment on the same flag:
        // without it, re-running this after a requirements change silently
        // keeps the old packages while pip still reports success.
        '--upgrade',
        '--no-warn-script-location',
        '--progress-bar', 'off',
      ],
      workingDirectory: baseDir.path,
    );

    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((l) => controller.add(ProvisionProgress(l)));
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((l) => controller.add(ProvisionProgress(l, isError: true)));

    unawaited(process.exitCode.then((code) async {
      if (code == 0) {
        await _marker.writeAsString(DateTime.now().toIso8601String());
        await controller.close();
      } else {
        controller.addError(
          Exception('Install failed (pip exited $code). Check your internet '
              'connection and try again.'),
        );
        await controller.close();
      }
    }));

    yield* controller.stream;
  }

  /// Removes everything this component installed. Callers stop it first if
  /// it's a running [ComponentKind.server] — see `ComponentManager.uninstall`.
  Future<void> delete() async {
    if (await baseDir.exists()) {
      await baseDir.delete(recursive: true);
    }
  }

  /// Runs `python -m [moduleName] args...` against this component's isolated
  /// [sitePackages], as a one-shot subprocess — for [ComponentKind.tool]
  /// components, which have no persistent process to talk to (contrast
  /// `SearxngSupervisor`, which owns a long-lived one for the `server` kind).
  ///
  /// A non-zero exit code is left for the caller to inspect via the returned
  /// [ProcessResult] rather than treated as an error here — e.g. yt-dlp's own
  /// exit codes carry meaning a caller may want to branch on.
  Future<ProcessResult> runModule(
    String moduleName,
    List<String> args, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final bootstrap = await materializeAsset('run_tool_bootstrap.py');
    final process = await Process.start(
      BackendRuntime.pythonExe.path,
      [bootstrap.path, moduleName, ...args],
      workingDirectory: baseDir.path,
      environment: {'MULTI_AI_COMPONENT_PATH': sitePackages.path},
    );
    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();
    final exitCode = await process.exitCode.timeout(
      timeout,
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    return ProcessResult(process.pid, exitCode, await stdoutFuture, await stderrFuture);
  }
}
