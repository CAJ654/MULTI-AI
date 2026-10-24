import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter/foundation.dart';

import '../../api_client.dart' show ModelInfo;
import '../../model_pool.dart';
import 'antigravity_settings.dart';
import 'local_model_server.dart';

enum AntigravityServerState { stopped, starting, running, error }

/// Builds the server the controller drives. Injectable so tests can swap in
/// one backed by a fake generate function instead of a real [ModelPool].
typedef LocalModelServerFactory = LocalModelServer Function({
  required String Function() token,
  required String? Function() defaultModel,
  required void Function(ServerRequestLog log) onRequest,
});

/// Drives the Antigravity tab: whether the server is up, its settings, and a
/// short log of what it has served. Built once per enable by
/// [AntigravityAddOn.onEnable] and torn down (server stopped) in `onDisable`.
class AntigravityController extends ChangeNotifier {
  AntigravityController({
    required this.modelPool,
    AntigravitySettingsStore? store,
    LocalModelServerFactory? serverFactory,
  }) : _store = store ?? FileAntigravitySettingsStore() {
    _server = (serverFactory ?? _defaultServer)(
      token: () => settings.bearerToken,
      defaultModel: () => settings.modelId,
      onRequest: _onRequest,
    );
    modelPool.addListener(notifyListeners);
    unawaited(_load());
  }

  /// How many requests the activity log keeps.
  static const logLimit = 50;

  final ModelPool modelPool;
  final AntigravitySettingsStore _store;
  late final LocalModelServer _server;

  /// Starts as defaults and is replaced by what's on disk once [_load]
  /// finishes — enabling an add-on can't await file IO (it never completes
  /// under flutter_test's fake-async), so the pane renders first and fills in.
  AntigravitySettings settings = AntigravitySettings.defaults();

  AntigravityServerState state = AntigravityServerState.stopped;

  /// One sentence for the pane when [state] is [AntigravityServerState.error].
  String? error;

  /// Newest first, capped at [logLimit].
  List<ServerRequestLog> log = const [];

  bool _disposed = false;

  bool get running => state == AntigravityServerState.running;

  /// What to give the Antigravity proxy as its OpenAI base URL.
  String get baseUrl => 'http://127.0.0.1:${_server.port ?? settings.port}/v1';

  /// The model requests fall back to, mirroring what the server will do: the
  /// saved choice if it's still downloaded, otherwise the first one that is.
  ModelInfo? get defaultModel {
    final downloaded = modelPool.downloaded;
    for (final model in downloaded) {
      if (model.id == settings.modelId) {
        return model;
      }
    }
    return downloaded.isEmpty ? null : downloaded.first;
  }

  LocalModelServer _defaultServer({
    required String Function() token,
    required String? Function() defaultModel,
    required void Function(ServerRequestLog log) onRequest,
  }) {
    return LocalModelServer(
      token: token,
      defaultModel: defaultModel,
      onRequest: onRequest,
      models: () => [for (final m in modelPool.downloaded) m.id],
      cancel: modelPool.cancel,
      generate: (modelId, prompt, history) {
        final model = modelPool.downloaded.firstWhere((m) => m.id == modelId);
        return modelPool.generate(model: model, prompt: prompt, history: history);
      },
    );
  }

  Future<void> _load() async {
    final loaded = await _store.load();
    if (_disposed) {
      return;
    }
    settings = loaded;
    // Persist straight away so a first-run token is the same one next launch
    // — a store with no file yet hands back a freshly generated one each time.
    await _store.save(settings);
    notifyListeners();
    if (settings.autoStart && state == AntigravityServerState.stopped) {
      await start();
    }
  }

  Future<void> start() async {
    if (state == AntigravityServerState.starting || running) {
      return;
    }
    state = AntigravityServerState.starting;
    error = null;
    notifyListeners();
    try {
      await _server.start(settings.port);
      state = AntigravityServerState.running;
    } on SocketException {
      state = AntigravityServerState.error;
      error = 'Port ${settings.port} is already in use. Pick another one.';
    } catch (e) {
      state = AntigravityServerState.error;
      error = 'Could not start the server: $e';
    }
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> stop() async {
    await _server.stop();
    state = AntigravityServerState.stopped;
    error = null;
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// Ignored while running — the port is bound until the server stops.
  Future<void> setPort(int port) async {
    if (running || port < 1 || port > 65535) {
      return;
    }
    await _update(settings.copyWith(port: port));
  }

  Future<void> selectModel(ModelInfo model) => _update(settings.copyWith(modelId: model.id));

  Future<void> setAutoStart(bool value) => _update(settings.copyWith(autoStart: value));

  /// Invalidates the old token immediately — the server reads it per request.
  Future<void> regenerateToken() => _update(settings.copyWith(bearerToken: generateBearerToken()));

  Future<void> _update(AntigravitySettings next) async {
    settings = next;
    notifyListeners();
    await _store.save(next);
  }

  void _onRequest(ServerRequestLog entry) {
    if (_disposed) {
      return;
    }
    log = [entry, ...log].take(logLimit).toList();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    modelPool.removeListener(notifyListeners);
    unawaited(_server.stop());
    super.dispose();
  }
}
