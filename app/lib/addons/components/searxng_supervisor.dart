// Owns the SearXNG child process for as long as it's needed.
//
// A concrete mirror of BackendSupervisor (backend_process.dart) rather than a
// shared abstraction over both — the two differ in enough small ways (a
// generated settings file, a different readiness route, no adoption of a
// developer's hand-started server) that a shared base class would mostly be
// parameters threading those differences through, which reads worse than two
// short, separately readable classes.
//
// Ports in use by this app, so a future addition doesn't collide: main
// backend 8000 (backend_process.dart), Colibri 8010
// (Multi-AI/multi_ai/server.pyx), SearXNG 8891 (here).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import '../../backend_process.dart' show BackendRuntime;
import 'component.dart';
import 'component_runtime.dart';

class SearxngSupervisor {
  SearxngSupervisor(this._runtime)
      : assert(_runtime.component.id == 'searxng',
            'SearxngSupervisor only manages the searxng component');

  final ComponentRuntime _runtime;
  Process? _process;

  /// True once this process has answered a health check.
  bool get isRunning => _process != null;

  static int get _port => componentById('searxng')!.port!;

  /// Whether *something* is already answering on SearXNG's port — checked
  /// before spawning so a process this app started earlier (and never
  /// stopped, e.g. after a hot-reload during development) is adopted rather
  /// than raced against for the port.
  static Future<bool> ping({Duration timeout = const Duration(seconds: 1)}) async {
    try {
      final response =
          await http.get(Uri.parse('http://127.0.0.1:$_port/')).timeout(timeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Writes settings.yml on first call and reuses it after — in particular
  /// its randomly generated secret key is meant to persist, not rotate on
  /// every start.
  Future<File> _ensureSettingsFile() async {
    final file = File('${_runtime.baseDir.path}\\settings.yml');
    if (await file.exists()) return file;
    final template =
        await rootBundle.loadString('assets/components/searxng_settings.yml.tmpl');
    final secretKeyBytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    final secretKey = base64Url.encode(secretKeyBytes);
    await file.parent.create(recursive: true);
    await file.writeAsString(template.replaceAll('__SECRET_KEY__', secretKey));
    return file;
  }

  /// Starts SearXNG and waits for it to answer. No-op if something already is.
  ///
  /// Throws [StateError] if the component isn't installed yet, [Exception] if
  /// the process exits during startup, and [TimeoutException] if it never
  /// becomes healthy in time — the caller (see `ComponentManager.ensureRunning`)
  /// turns each into a message Chat's grounding step can fall back around.
  Future<void> start({Duration timeout = const Duration(seconds: 30)}) async {
    if (await ping()) return;
    if (!ComponentRuntime.available) return;
    if (!_runtime.isInstalled) {
      throw StateError(
          "Web search isn't installed yet — install it from the Add-ons tab.");
    }

    final settingsFile = await _ensureSettingsFile();
    final bootstrap =
        await _runtime.materializeAsset('searxng_bootstrap.py', into: 'bootstrap.py');

    _process = await Process.start(
      BackendRuntime.pythonExe.path,
      [bootstrap.path],
      workingDirectory: _runtime.baseDir.path,
      environment: {
        'MULTI_AI_COMPONENT_PATH': _runtime.sitePackages.path,
        'SEARXNG_SETTINGS_PATH': settingsFile.path,
      },
    );

    // Drained rather than ignored — see BackendSupervisor.start()'s identical
    // comment: an unread pipe fills its buffer and blocks the child mid-write.
    final log = StringBuffer();
    _process!.stdout.transform(utf8.decoder).listen(log.write);
    _process!.stderr.transform(utf8.decoder).listen(log.write);

    var exited = false;
    unawaited(_process!.exitCode.then((_) => exited = true));

    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (exited) {
        _process = null;
        throw Exception('Web search exited during startup.\n\n$log');
      }
      if (await ping()) return;
      await Future.delayed(const Duration(milliseconds: 400));
    }
    await stop();
    throw TimeoutException(
      'Web search did not respond within ${timeout.inSeconds}s.\n\n$log',
    );
  }

  /// Stops the process if this supervisor started one. Called on app exit and
  /// when the component is uninstalled — see `ComponentManager`.
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
