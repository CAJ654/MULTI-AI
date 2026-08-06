import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:llamadart/llamadart.dart' hide ChatSession;

import 'api_client.dart';
import 'on_device_engine.dart';

/// The model roster, which of it is downloaded, and the one way to actually run
/// something — shared by every add-on rather than owned by the chat screen.
///
/// This exists because the choice between the two run paths (a `gguf` source
/// goes to llama.cpp in-process; everything else goes to the Python backend)
/// used to be inline in the chat screen's send handler, reading private state.
/// Anything else that wants to ask a model a question — an orchestration
/// add-on running the same prompt past several models, say — needs that
/// decision to live somewhere it can be called from.
///
/// Notably *not* here: which model is selected. That is per-add-on state — chat
/// picks one, orchestration will pick several plus a lead — so each owns its
/// own rather than fighting over a shared one.
class ModelPool extends ChangeNotifier {
  ModelPool({
    ApiClient? api,
    OnDeviceEngine? engine,
    ModelDownloadManager? downloadManager,
  })  : api = api ?? ApiClient(),
        _engine = engine ?? OnDeviceEngine(),
        _downloads = downloadManager ?? DefaultModelDownloadManager();

  /// The backend client. Public because a server-backed model's weights are
  /// downloaded and deleted from its detail page, which talks to the backend
  /// directly rather than through this class.
  final ApiClient api;

  final OnDeviceEngine _engine;
  final ModelDownloadManager _downloads;

  /// The model that ships with the app. It needs no server, so it's in the
  /// roster even when the backend can't be reached.
  static const ModelInfo builtInOnDevice = ModelInfo(
    id: onDeviceModelId,
    name: onDeviceModelName,
    available: true,
    // Rated here rather than by the backend, which doesn't know about this
    // entry: at half a gigabyte it clears any machine that can run the app,
    // so the verdict doesn't depend on the specs we may not have yet.
    fit: ModelFit(
      rating: ModelFitRating.optimal,
      reason: 'Half a gigabyte — runs comfortably on any machine that runs this app.',
      needsGb: onDeviceModelSizeGb,
    ),
    params: onDeviceModelParams,
    sizeGb: onDeviceModelSizeGb,
    modality: onDeviceModelModality,
    contextTokens: onDeviceModelContextTokens,
    license: onDeviceModelLicense,
    strengths: onDeviceModelStrengths,
    speedProfile: onDeviceModelSpeedProfile,
  );

  List<ModelInfo> _models = const [];
  Set<String> _downloadedIds = const {};
  DeviceSpecs? _deviceSpecs;
  bool _loading = true;
  bool _checkingDownloads = true;
  String? _loadError;

  List<ModelInfo> get models => List.unmodifiable(_models);

  /// Ids of models whose weights are actually present — an on-device cache hit,
  /// or the backend reporting one in its Hugging Face cache.
  Set<String> get downloadedIds => Set.unmodifiable(_downloadedIds);

  /// The subset that can be chatted with right now. Offering an undownloaded
  /// model would silently kick off a multi-gigabyte download on first send.
  List<ModelInfo> get downloaded =>
      _models.where((m) => _downloadedIds.contains(m.id)).toList();

  /// The backend machine's hardware, for captioning the fit badges. Null until
  /// it loads, and on a backend too old to report it.
  DeviceSpecs? get deviceSpecs => _deviceSpecs;

  bool get loading => _loading;
  bool get checkingDownloads => _checkingDownloads;

  /// Set when the backend couldn't be reached — the roster then holds only
  /// [builtInOnDevice].
  String? get loadError => _loadError;

  /// True once both the roster and its download state have settled. Callers
  /// that reconcile a selection against [downloaded] should wait for this;
  /// mid-refresh the two are briefly inconsistent.
  bool get ready => !_loading && !_checkingDownloads;

  /// Which llama.cpp source [m] runs from, or null if it runs on the server.
  static String? localSourceOf(ModelInfo m) =>
      m.id == onDeviceModelId ? onDeviceModelSource : m.gguf;

  Future<void> refresh() async {
    _loading = true;
    _loadError = null;
    notifyListeners();
    try {
      final serverModels = await api.fetchModels();
      _models = [builtInOnDevice, ...serverModels];
      notifyListeners();
      // Context for the fit badges: which machine they were judged against.
      // Best-effort — an older backend has no /api/device, and a missing
      // header is a much smaller loss than a failed model list.
      try {
        _deviceSpecs = await api.fetchDeviceSpecs();
        notifyListeners();
      } catch (_) {
        // Leave the header off.
      }
    } catch (e) {
      _models = const [builtInOnDevice];
      _loadError = 'Backend unreachable — only the on-device model is available.';
    } finally {
      _loading = false;
      // No notify here: refreshDownloaded's first act is to flip
      // checkingDownloads back on, so listeners would otherwise see one frame
      // where the pool claims to be ready with stale download state.
    }
    await refreshDownloaded();
  }

  Future<bool> isDownloaded(ModelInfo m) async {
    if (!m.available) return false;
    // A BYO external-server model (e.g. Colibri) has no weights this app
    // downloads or caches — it's either ready to chat with (if the user's
    // own server is running) or fails with a clear error at chat time, never
    // "not downloaded". Calling the server-cache-status endpoint for one of
    // these always throws (no _REPO_ID to check), which used to be caught
    // and misread as "not downloaded" forever.
    if (m.externalEndpoint != null) return true;
    final source = localSourceOf(m);
    if (source != null) {
      final entry = await _downloads.get(ModelSource.parse(source).cacheKey);
      if (entry == null) return false;
      // A vision model whose projector is missing would load and chat but
      // silently fail to see, after the + button had already been offered —
      // so it doesn't count as downloaded until both files are present.
      final mmproj = m.mmproj;
      if (mmproj != null) {
        return await _downloads.get(ModelSource.parse(mmproj).cacheKey) != null;
      }
      return true;
    }
    try {
      final status = await api.getServerModelCacheStatus(m.id);
      return status.cached;
    } catch (_) {
      return false;
    }
  }

  /// Re-checks which models are actually downloaded — called after the roster
  /// loads and again whenever a model's detail page closes, since downloads and
  /// deletes happen there.
  Future<void> refreshDownloaded() async {
    _checkingDownloads = true;
    notifyListeners();
    final models = _models;
    final flags = await Future.wait(models.map(isDownloaded));
    _downloadedIds = {
      for (var i = 0; i < models.length; i++)
        if (flags[i]) models[i].id,
    };
    _checkingDownloads = false;
    notifyListeners();
  }

  /// Chains on-device generations so they can't overlap. See [generate].
  Future<void> _onDeviceQueue = Future.value();

  /// Runs [prompt] past [model] and returns its reply, taking whichever of the
  /// two run paths that model declares.
  Future<String> generate({
    required ModelInfo model,
    required String prompt,
    List<ChatTurn> history = const [],
    List<Attachment> attachments = const [],
  }) {
    final source = localSourceOf(model);
    if (source == null) {
      // Server models are stateless per request and can overlap freely.
      return api.sendChat(
        model: model.id,
        message: prompt,
        attachments: attachments,
        history: history,
      );
    }
    // On-device is a different story: OnDeviceEngine keeps exactly one model
    // resident and evicts on switch, so two concurrent calls for different
    // GGUFs would thrash multi-gigabyte loads against each other. Queue them.
    // (The engine guards its own decode loop, but not this.)
    final sizeGb = model.id == onDeviceModelId ? onDeviceModelSizeGb : model.sizeGb;
    final turn = _onDeviceQueue.then((_) => _engine.generate(
          prompt,
          source: source,
          sizeGb: sizeGb,
          mmproj: model.mmproj,
          attachments: attachments,
          history: history,
        ));
    // The queue tracks completion only — a failed or cancelled generation must
    // not poison the turns behind it.
    _onDeviceQueue = turn.then((_) {}, onError: (_) {});
    return turn;
  }

  /// Aborts whatever is generating. Both paths, because the caller doesn't
  /// necessarily know which one its reply is coming from.
  void cancel() {
    api.cancelChat();
    _engine.stop();
  }

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }
}
