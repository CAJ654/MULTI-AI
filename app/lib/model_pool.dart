import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:llamadart/llamadart.dart' hide ChatSession;
import 'package:path_provider/path_provider.dart' show getApplicationSupportDirectory;

import 'api_client.dart';
import 'device_fit.dart';
import 'download_foreground_service.dart';
import 'on_device_engine.dart';
import 'platform_check.dart';

/// True on Android: on-device GGUF only, the phone never talks to the Python
/// backend — see api_client.dart's apiBaseUrl comment for the same scoping
/// decision on the network side. A top-level getter (not a ModelPool member)
/// so model_detail_screen.dart's independent download manager can check the
/// same condition without depending on a ModelPool instance.
///
/// Deliberately `isAndroidHost` (real OS-level check), not
/// `defaultTargetPlatform` — the latter is overridden to
/// `TargetPlatform.android` by the `flutter_test` binding regardless of host
/// OS, which would make every widget test take this branch.
bool get isAndroidPlatform => !kIsWeb && isAndroidHost;

/// Durable, app-private directory for on-device model weights on Android.
/// [DefaultModelDownloadManager]'s bare constructor falls back to the
/// OS-purgeable temp/cache directory there — this is the fix, shared so
/// ModelPool, OnDeviceEngine (via ModelPool), and ModelDetailScreen's own
/// download manager/controller all agree on one location rather than three
/// independently-computed paths that could drift apart.
Future<String> androidModelCacheDirectory() async {
  final dir = await getApplicationSupportDirectory();
  return '${dir.path}/llamadart_models';
}

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

  /// Android's durable cache-directory override, resolved once and reused —
  /// see [_effectiveDownloads]. Null on every other platform, where [_downloads]
  /// (constructed synchronously above) is used directly.
  ModelDownloadManager? _androidDownloadsOverride;

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

  /// Set when the backend couldn't be reached, or when it could but the
  /// bundled on-device roster it fell back to is itself missing/malformed.
  /// Either way the roster still holds whatever [_refreshFromBundledRoster]
  /// managed to load — at minimum [builtInOnDevice].
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
    if (isAndroidPlatform) {
      await _refreshFromBundledRoster();
    } else {
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
        // No reachable backend doesn't have to mean no models: the same
        // bundled on-device roster Android always uses is right here too,
        // so fall back to it instead of collapsing to just builtInOnDevice.
        await _refreshFromBundledRoster();
        // _refreshFromBundledRoster only sets _loadError itself when the
        // asset is missing/malformed — a real problem distinct from "no
        // backend". If it loaded fine, the backend is the actual story.
        _loadError ??= 'Backend unreachable — showing on-device models only.';
      }
    }
    _loading = false;
    // No notify here: refreshDownloaded's first act is to flip
    // checkingDownloads back on, so listeners would otherwise see one frame
    // where the pool claims to be ready with stale download state.
    await refreshDownloaded();
  }

  /// Loads the on-device roster from its build-time asset rather than a
  /// backend — Android always takes this path (no reachable backend by
  /// design), and every other platform falls back to it in [refresh] when
  /// the backend can't be reached. See tool/generate_on_device_roster.dart,
  /// which must be re-run whenever Multi-AI/multi_ai/models/*.pyx changes
  /// and before any build.
  ///
  /// The asset carries no `fit` — it's generated statically and can't know
  /// the runtime device's hardware — so every entry is annotated here with
  /// a rating computed against this device's own RAM (see device_fit.dart).
  /// [builtInOnDevice] keeps its own hardcoded rating rather than going
  /// through this: it's small enough that any machine capable of running
  /// this app runs it, so the verdict doesn't depend on specs that may not
  /// even be readable yet.
  Future<void> _refreshFromBundledRoster() async {
    try {
      final raw = await rootBundle.loadString('assets/on_device_roster.json');
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final rosterModels = (data['models'] as List<dynamic>)
          .map((m) => ModelInfo.fromJson(m as Map<String, dynamic>))
          .toList();
      final fits = await Future.wait(rosterModels.map((m) => rateOnDeviceModel(m.sizeGb)));
      _models = [
        builtInOnDevice,
        for (var i = 0; i < rosterModels.length; i++) rosterModels[i].copyWithFit(fits[i]),
      ];
    } catch (e) {
      // Missing/malformed asset is a genuine build problem, not a normal
      // offline state — there's no backend to blame as "unreachable" here,
      // so that message would be actively misleading. Still surface
      // something rather than silently offering only builtInOnDevice.
      _models = const [builtInOnDevice];
      _loadError = 'On-device model roster failed to load '
          '(assets/on_device_roster.json missing or malformed) — only the '
          'built-in model is available.';
    }
  }

  /// The download manager to use for cache-status checks and — via
  /// [OnDeviceEngine.downloadManager] — actual weight downloads. On Android,
  /// resolves once to a durable app-support directory instead of
  /// [DefaultModelDownloadManager]'s bare-constructor fallback, which on
  /// Android lands in the OS-purgeable temp/cache directory rather than
  /// durable storage. Every other platform keeps today's behavior unchanged.
  Future<ModelDownloadManager> get _effectiveDownloads async {
    if (isAndroidPlatform) {
      final resolved = _androidDownloadsOverride ??= DefaultModelDownloadManager.appPrivate(
        cacheDirectory: await androidModelCacheDirectory(),
      );
      // Threaded into the engine too — otherwise generate() would still
      // download through LlamaEngine's own unconfigured default manager, a
      // split-brain where isDownloaded() checks one directory while the
      // actual download lands in another.
      _engine.downloadManager ??= resolved;
      return resolved;
    }
    return _downloads;
  }

  Future<bool> isDownloaded(ModelInfo m) async {
    if (!m.available) return false;
    // A BYO external-server model with no server-managed weights (i.e. no
    // hasServerWeights) has nothing this app downloads or caches — it's
    // either ready to chat with (if the user's own server is running) or
    // fails with a clear error at chat time, never "not downloaded". Calling
    // the server-cache-status endpoint for one of these always throws (no
    // _REPO_ID to check), which used to be caught and misread as "not
    // downloaded" forever. A Colibri model with hasServerWeights genuinely
    // can be undownloaded (167GB-1.6TB weights), so it falls through to the
    // real cache-status check below like any other server-managed model.
    if (m.externalEndpoint != null && !m.hasServerWeights) return true;
    final source = localSourceOf(m);
    if (source != null) {
      final downloads = await _effectiveDownloads;
      final entry = await downloads.get(ModelSource.parse(source).cacheKey);
      if (entry == null) return false;
      // A vision model whose projector is missing would load and chat but
      // silently fail to see, after the + button had already been offered —
      // so it doesn't count as downloaded until both files are present.
      final mmproj = m.mmproj;
      if (mmproj != null) {
        return await downloads.get(ModelSource.parse(mmproj).cacheKey) != null;
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

  /// One controller per model id, created lazily on first download and kept
  /// for the pool's lifetime — not the requesting widget's. A
  /// [ModelDetailScreen] that's popped mid-download used to dispose (and
  /// thus cancel, via llamadart's ModelDownloadController.dispose ->
  /// cancel()) the controller it owned itself; navigating away is not the
  /// same as wanting the download stopped, so ownership lives here instead,
  /// above the navigation stack. Re-opening the same model's detail page
  /// reattaches to this same controller and its live snapshot rather than
  /// starting a duplicate.
  final Map<String, ModelDownloadController> _downloadControllers = {};

  /// How many on-device downloads are running right now — drives the
  /// Android foreground-service notification (see
  /// [DownloadForegroundService]), which needs to start on 0->1 and stop on
  /// 1->0 rather than once per download.
  int _activeDownloadCount = 0;

  /// Current progress/result of [id]'s on-device download this session, or
  /// null if none has ever run. Read by [ModelDetailScreen] instead of
  /// owning a controller itself.
  ModelDownloadTaskSnapshot? downloadSnapshotFor(String id) =>
      _downloadControllers[id]?.snapshot;

  /// Starts (or reattaches to) [model]'s on-device download. Safe to call
  /// repeatedly — a controller already running is left alone rather than
  /// restarted. Listeners are notified as progress comes in (via the
  /// controller's snapshot stream) and once more when [refreshDownloaded]
  /// picks up the result, so callers that only want to observe an
  /// in-flight download don't need to await this themselves.
  Future<void> ensureOnDeviceDownload(ModelInfo model) async {
    final source = localSourceOf(model);
    if (source == null) return;
    var controller = _downloadControllers[model.id];
    if (controller != null) {
      if (controller.snapshot.isRunning) return;
    } else {
      controller = ModelDownloadController(manager: await _effectiveDownloads);
      _downloadControllers[model.id] = controller;
      controller.snapshots.listen((_) => notifyListeners());
    }
    _activeDownloadCount++;
    if (_activeDownloadCount == 1) DownloadForegroundService.start();
    notifyListeners();
    try {
      await controller.start(ModelSource.parse(source));
      final mmproj = model.mmproj;
      if (mmproj != null) {
        await (await _effectiveDownloads).ensureModel(ModelSource.parse(mmproj));
      }
    } catch (_) {
      // Failure/cancellation is already reflected in the controller's
      // snapshot — nothing more to do here.
    } finally {
      _activeDownloadCount--;
      if (_activeDownloadCount == 0) DownloadForegroundService.stop();
      await refreshDownloaded();
    }
  }

  /// Cancels [id]'s in-flight on-device download, if any.
  void cancelDownload(String id) => _downloadControllers[id]?.cancel();

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
    for (final controller in _downloadControllers.values) {
      controller.dispose();
    }
    _engine.dispose();
    super.dispose();
  }
}
