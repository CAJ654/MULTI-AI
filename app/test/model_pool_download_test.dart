// Regression coverage for the download-lifecycle fix: an on-device download
// used to be owned by ModelDetailScreen's State, so popping that page (to
// browse other models, or because the app backgrounded) disposed its
// ModelDownloadController — and llamadart's dispose() cancels first. Moving
// ownership into ModelPool (see model_pool.dart's ensureOnDeviceDownload)
// means nothing tied to a widget's lifetime can cancel it anymore; these
// tests exercise ModelPool directly, without any widget in the picture, to
// prove the download itself no longer depends on one being mounted.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart/llamadart.dart';
import 'package:multi_ai/api_client.dart';
import 'package:multi_ai/model_pool.dart';

/// Returns a canned single on-device model instead of calling a real backend.
class _FakeApiClient extends ApiClient {
  _FakeApiClient(this.models);
  final List<ModelInfo> models;

  @override
  Future<List<ModelInfo>> fetchModels() async => models;

  @override
  Future<DeviceSpecs> fetchDeviceSpecs() async => throw Exception('no /api/device');
}

/// A download manager whose ensureModel() blocks on a gate the test controls,
/// so a test can inspect "downloading" state before letting it finish —
/// something the real network-backed default manager gives no hook for.
class _ControllableDownloadManager extends ThrowingModelDownloadManager {
  final Map<String, ModelCacheEntry> _cache = {};
  final Map<String, Completer<void>> _gates = {};
  int ensureModelCalls = 0;

  Completer<void> gateFor(String cacheKey) =>
      _gates.putIfAbsent(cacheKey, () => Completer<void>());

  @override
  Future<ModelCacheEntry?> get(String cacheKey, {String? cacheDirectory}) async => _cache[cacheKey];

  @override
  Future<ModelCacheEntry> ensureModel(
    ModelSource source, {
    ModelLoadOptions options = ModelLoadOptions.defaults,
    ModelDownloadProgressCallback? onProgress,
  }) async {
    ensureModelCalls++;
    // Real download managers poll their cancel token cooperatively (there's
    // no async notification on ModelDownloadCancelToken, just a synchronous
    // isCancelled flag) — mirrored here rather than just awaiting the gate,
    // so a cancel() call actually unblocks a download this fake is holding
    // open instead of hanging forever.
    final gate = gateFor(source.cacheKey);
    final cancelToken = options.cancelToken;
    while (!gate.isCompleted) {
      if (cancelToken?.isCancelled ?? false) {
        throw Exception('cancelled');
      }
      await Future.any<void>([
        gate.future,
        Future<void>.delayed(const Duration(milliseconds: 5)),
      ]);
    }
    final now = DateTime.now().toUtc();
    final entry = ModelCacheEntry(
      sourceCanonicalKey: source.cacheKey,
      cacheKey: source.cacheKey,
      fileName: 'fake.gguf',
      filePath: 'C:/fake-cache/fake.gguf',
      createdAt: now,
      updatedAt: now,
      bytes: 1,
    );
    _cache[source.cacheKey] = entry;
    return entry;
  }
}

const _gguf = 'hf://owner/repo/model.gguf';
const _model = ModelInfo(id: 'm1', name: 'Test On-Device Model', gguf: _gguf);

void main() {
  late _ControllableDownloadManager manager;
  late ModelPool pool;

  setUp(() async {
    manager = _ControllableDownloadManager();
    pool = ModelPool(api: _FakeApiClient(const [_model]), downloadManager: manager);
    await pool.refresh();
  });

  tearDown(() => pool.dispose());

  test('a download in progress has no dependency on anything staying mounted '
      'to keep running', () async {
    final download = pool.ensureOnDeviceDownload(_model);
    await Future.delayed(Duration.zero);
    expect(pool.downloadSnapshotFor('m1')?.isRunning, isTrue);

    // The old bug was a screen's dispose() cancelling the controller it
    // owned. There is nothing here playing that role — ModelPool isn't
    // disposed by navigation, only by the app itself — so the download
    // should still be exactly where it was left, then complete normally
    // once its network call (the gate) resolves.
    manager.gateFor(ModelSource.parse(_gguf).cacheKey).complete();
    await download;

    expect(pool.downloadSnapshotFor('m1')?.stage, ModelDownloadTaskStage.ready);
    expect(pool.downloadedIds, contains('m1'));
  });

  test('calling ensureOnDeviceDownload again while one is already running '
      'reattaches instead of starting a second one', () async {
    final first = pool.ensureOnDeviceDownload(_model);
    await Future.delayed(Duration.zero);
    expect(manager.ensureModelCalls, 1);

    // Simulates re-opening the same model's detail page while its download
    // is still in flight.
    final second = pool.ensureOnDeviceDownload(_model);
    await Future.delayed(Duration.zero);
    expect(manager.ensureModelCalls, 1, reason: 'reattached, not restarted');

    manager.gateFor(ModelSource.parse(_gguf).cacheKey).complete();
    await Future.wait([first, second]);
    expect(pool.downloadedIds, contains('m1'));
  });

  test('cancelDownload stops the in-flight download without downloading it',
      () async {
    final download = pool.ensureOnDeviceDownload(_model);
    await Future.delayed(Duration.zero);
    expect(pool.downloadSnapshotFor('m1')?.isRunning, isTrue);

    pool.cancelDownload('m1');
    await download;

    expect(pool.downloadSnapshotFor('m1')?.stage, ModelDownloadTaskStage.cancelled);
    expect(pool.downloadedIds, isNot(contains('m1')));
  });
}
