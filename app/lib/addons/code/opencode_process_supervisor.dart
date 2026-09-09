import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../chat_store.dart' show appDataFile;
import 'llama_server_supervisor.dart';

/// Owns the single `opencode serve` child process the Code tab drives
/// through `opencode_client.dart`. Unlike [LlamaServerSupervisor] (restarted
/// whenever the selected model's GGUF file changes), this is started once,
/// lazily, on the Code tab's first message, and left running for the rest of
/// the app's life: opencode's server can host any number of project
/// directories/sessions at once via a `directory` query parameter on every
/// request (confirmed empirically against a running server — not
/// documented), so a project-root change needs no restart here, only a new
/// session created against the new directory.
///
/// Mirrors `SearxngSupervisor` for the process-lifecycle shape (ping before
/// spawning, drain output, health-poll, stop/kill).
///
/// Ports in use: see `searxng_supervisor.dart`'s header comment — this adds
/// 8101.
class OpencodeProcessSupervisor {
  static const port = 8101;
  static const baseUrl = 'http://127.0.0.1:$port';

  /// The provider/model ids the generated config below registers — a fixed
  /// custom provider pointing at [LlamaServerSupervisor], not one of
  /// opencode's built-in hosted ones.
  static const providerId = 'multiai-local';
  static const modelId = 'local';

  Process? _process;

  bool get isRunning => _process != null;

  static Future<bool> ping({Duration timeout = const Duration(seconds: 1)}) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/config')).timeout(timeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _onPath() async {
    try {
      final result = await Process.run(Platform.isWindows ? 'where' : 'which', ['opencode']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Points opencode at [LlamaServerSupervisor]'s OpenAI-compatible endpoint
  /// as a custom provider, and tightens its default permissions to this
  /// app's own gated-tool set (`edit`/`bash` ask — matches the read-tools-
  /// always-proceed / write-tools-gated split the old `agent_tools.dart`
  /// enforced by hand; `webfetch`/`websearch` off — the Code tab has no UI
  /// for either).
  ///
  /// Written to this app's own data directory and passed via `OPENCODE_CONFIG`
  /// rather than into the project folder or opencode's own global config:
  /// `PATCH /config?directory=<dir>` (the alternative, runtime-only way to
  /// set this) was confirmed to write a `config.json` straight into that
  /// directory — fine for opencode's own projects, not something this app
  /// should drop into an arbitrary user project.
  Future<File> _writeConfig() async {
    final file = await appDataFile('opencode_config.json');
    await file.writeAsString(jsonEncode({
      r'$schema': 'https://opencode.ai/config.json',
      'provider': {
        providerId: {
          'npm': '@ai-sdk/openai-compatible',
          'name': 'MULTI-AI (on-device)',
          'options': {'baseURL': 'http://127.0.0.1:${LlamaServerSupervisor.port}/v1'},
          'models': {
            modelId: {'name': 'On-device GGUF'},
          },
        },
      },
      'permission': {
        'edit': 'ask',
        'bash': 'ask',
        'webfetch': 'deny',
        'websearch': 'deny',
      },
    }));
    return file;
  }

  /// Starts `opencode serve` if nothing is already answering on [port]. See
  /// this class's doc comment for why a project-root or model change never
  /// needs a restart here.
  ///
  /// Throws [StateError] if the binary isn't on PATH, [Exception] if the
  /// process exits during startup, and [TimeoutException] if it never
  /// becomes healthy in time.
  Future<void> start({Duration timeout = const Duration(seconds: 20)}) async {
    if (await ping()) return;

    if (!await _onPath()) {
      throw StateError(
        "opencode isn't installed (or isn't on PATH) — install it once "
        '(curl -fsSL https://opencode.ai/install | bash, or see '
        'https://opencode.ai), then try again.',
      );
    }

    final configFile = await _writeConfig();

    _process = await Process.start(
      'opencode',
      ['serve', '--port', '$port', '--hostname', '127.0.0.1'],
      environment: {'OPENCODE_CONFIG': configFile.path},
    );

    final log = StringBuffer();
    _process!.stdout.transform(utf8.decoder).listen(log.write);
    _process!.stderr.transform(utf8.decoder).listen(log.write);

    var exited = false;
    unawaited(_process!.exitCode.then((_) => exited = true));

    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (exited) {
        _process = null;
        throw Exception('opencode serve exited during startup.\n\n$log');
      }
      if (await ping()) return;
      await Future.delayed(const Duration(milliseconds: 300));
    }
    await stop();
    throw TimeoutException('opencode serve did not respond within ${timeout.inSeconds}s.\n\n$log');
  }

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
