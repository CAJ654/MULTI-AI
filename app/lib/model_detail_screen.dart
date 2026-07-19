import 'dart:async';

import 'package:flutter/material.dart';
import 'package:llamadart/llamadart.dart';

import 'api_client.dart';
import 'theme.dart';

/// Full-page breakdown of a single model, pushed when its card is tapped in
/// the sidebar's Models tab (see `chat_screen.dart`'s `_buildModelCard`).
class ModelDetailScreen extends StatefulWidget {
  const ModelDetailScreen({
    super.key,
    required this.model,
    required this.runsInApp,
    this.source,
    this.api,
  });

  final ModelInfo model;

  /// Whether this model runs in-app via llama.cpp, vs. via the local Python
  /// backend. Both run entirely on this machine — see chat_screen.dart.
  final bool runsInApp;

  /// The llama.cpp model source (e.g. `hf://owner/repo/file.gguf`) used to
  /// resolve this model's on-device cache entry. Null for models that run via
  /// the local Python backend.
  final String? source;

  /// Backend client, passed for models that run via the local Python backend
  /// (`!runsInApp`) so this screen can check/download/delete that machine's
  /// cached weights for this model. Null for on-device models and for
  /// unavailable/stub entries with no weights to manage.
  final ApiClient? api;

  @override
  State<ModelDetailScreen> createState() => _ModelDetailScreenState();
}

class _ModelDetailScreenState extends State<ModelDetailScreen> {
  static const _unknown = 'Not documented for this model yet';

  final _downloadManager = DefaultModelDownloadManager();
  ModelDownloadController? _downloadController;
  StreamSubscription<ModelDownloadTaskSnapshot>? _downloadSub;

  bool _checkingCache = true;
  ModelCacheEntry? _cacheEntry;
  ModelDownloadTaskSnapshot? _downloadSnapshot;

  // Server-backed (_REPO_ID) model install state — same shape as the
  // on-device fields above, but driven by the Python backend's Hugging
  // Face cache instead of llama.cpp's DefaultModelDownloadManager.
  bool _checkingServerCache = true;
  ServerModelCacheStatus? _serverCacheStatus;
  bool _serverBusy = false;
  String? _serverError;

  bool get _isServerModel => !widget.runsInApp && widget.model.available && widget.api != null;

  ModelSource? get _parsedSource {
    final source = widget.source;
    if (source == null) return null;
    return ModelSource.parse(source);
  }

  /// The vision model's companion projector, when it has one. Downloaded and
  /// deleted alongside the weights — on its own it's useless, and without it
  /// the weights load but can't see.
  ModelSource? get _parsedMmproj {
    final mmproj = widget.model.mmproj;
    if (mmproj == null || !widget.runsInApp) return null;
    return ModelSource.parse(mmproj);
  }

  @override
  void initState() {
    super.initState();
    _refreshCacheStatus();
    _refreshServerCacheStatus();
  }

  @override
  void dispose() {
    _downloadSub?.cancel();
    _downloadController?.dispose();
    super.dispose();
  }

  Future<void> _refreshCacheStatus() async {
    final source = _parsedSource;
    if (source == null) {
      setState(() => _checkingCache = false);
      return;
    }
    var entry = await _downloadManager.get(source.cacheKey);
    // Same rule the chat picker applies: a vision model missing its projector
    // isn't downloaded, so this page keeps offering Download until both land.
    final mmproj = _parsedMmproj;
    if (entry != null && mmproj != null) {
      if (await _downloadManager.get(mmproj.cacheKey) == null) entry = null;
    }
    if (!mounted) return;
    setState(() {
      _cacheEntry = entry;
      _checkingCache = false;
    });
  }

  Future<void> _refreshServerCacheStatus() async {
    if (!_isServerModel) {
      setState(() => _checkingServerCache = false);
      return;
    }
    try {
      final status = await widget.api!.getServerModelCacheStatus(widget.model.id);
      if (!mounted) return;
      setState(() {
        _serverCacheStatus = status;
        _checkingServerCache = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _serverError = '$e';
        _checkingServerCache = false;
      });
    }
  }

  Future<void> _downloadServer() async {
    setState(() {
      _serverBusy = true;
      _serverError = null;
    });
    try {
      final status = await widget.api!.downloadServerModel(widget.model.id);
      if (!mounted) return;
      setState(() => _serverCacheStatus = status);
    } catch (e) {
      if (!mounted) return;
      setState(() => _serverError = '$e');
    } finally {
      if (mounted) setState(() => _serverBusy = false);
    }
  }

  Future<void> _deleteServer() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardColor,
        title: const Text('Delete model?', style: TextStyle(color: Colors.white)),
        content: Text(
          'This removes the downloaded ${widget.model.name} weights from the backend '
          "machine. You'll need to download it again to chat with it.",
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _serverBusy = true;
      _serverError = null;
    });
    try {
      final status = await widget.api!.deleteServerModel(widget.model.id);
      if (!mounted) return;
      setState(() => _serverCacheStatus = status);
    } catch (e) {
      if (!mounted) return;
      setState(() => _serverError = '$e');
    } finally {
      if (mounted) setState(() => _serverBusy = false);
    }
  }

  Future<void> _download() async {
    final source = _parsedSource;
    if (source == null) return;
    final controller = ModelDownloadController();
    _downloadController = controller;
    setState(() => _downloadSnapshot = controller.snapshot);
    _downloadSub = controller.snapshots.listen((snapshot) {
      if (!mounted) return;
      setState(() => _downloadSnapshot = snapshot);
    });
    try {
      final entry = await controller.start(source);
      // Then the projector, if this is a vision model. It's a fraction of the
      // weights' size and has no separate progress UI — the download simply
      // isn't reported complete until both files are in the cache, so the
      // chat picker can't offer image input against a half-downloaded model.
      final mmproj = _parsedMmproj;
      if (mmproj != null) await _downloadManager.ensureModel(mmproj);
      if (!mounted) return;
      setState(() {
        _cacheEntry = entry;
        _downloadSnapshot = null;
      });
    } catch (_) {
      // Failure/cancellation is already reflected in _downloadSnapshot.
    } finally {
      await _downloadSub?.cancel();
      _downloadSub = null;
      await controller.dispose();
      if (identical(_downloadController, controller)) _downloadController = null;
    }
  }

  void _cancelDownload() => _downloadController?.cancel();

  Future<void> _delete() async {
    final source = _parsedSource;
    final entry = _cacheEntry;
    if (source == null || entry == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardColor,
        title: const Text('Delete model?', style: TextStyle(color: Colors.white)),
        content: Text(
          'This removes the downloaded ${widget.model.name} file from this device. '
          "You'll need to download it again to use it in-app.",
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _downloadManager.remove(source.cacheKey);
    // The projector is dead weight without its model — leaving it behind
    // would silently keep hundreds of MB on a device the user just freed.
    final mmproj = _parsedMmproj;
    if (mmproj != null) await _downloadManager.remove(mmproj.cacheKey);
    if (!mounted) return;
    setState(() => _cacheEntry = null);
  }

  String _formatContext(int? tokens) {
    if (tokens == null) return _unknown;
    if (tokens % 1024 == 0) return '${tokens ~/ 1024}K tokens';
    return '$tokens tokens';
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    return Scaffold(
      backgroundColor: mainColor,
      appBar: AppBar(
        backgroundColor: mainColor,
        elevation: 0,
        title: Text(model.name),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatsRow(),
                const SizedBox(height: 24),
                _buildInstallSection(),
                _buildServerInstallSection(),
                _buildSection(Icons.category_outlined, 'Modality', model.modalityLabel),
                _buildSection(
                  Icons.auto_awesome_outlined,
                  'Core Strengths & Intelligence Profile',
                  model.strengths ?? _unknown,
                ),
                _buildSection(
                  Icons.speed_outlined,
                  'Intelligence-to-Speed Ratio',
                  model.speedProfile ?? _unknown,
                ),
                _buildSection(
                  Icons.memory_outlined,
                  'Context Window',
                  _formatContext(model.contextTokens),
                ),
                _buildSection(Icons.gavel_outlined, 'Open Source License', model.license ?? _unknown),
                _buildSection(
                  widget.runsInApp ? Icons.smartphone_outlined : Icons.dns_outlined,
                  'Runs',
                  widget.runsInApp
                      ? 'In-app (llama.cpp) — no server needed'
                      : 'Local backend (Python, transformers)',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    final model = widget.model;
    return Row(
      children: [
        Expanded(child: _buildStatTile('Parameters', model.params ?? '—')),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatTile(
            'Download size',
            model.sizeGb != null ? '~${model.sizeGb!.toStringAsFixed(model.sizeGb! < 1 ? 2 : 1)} GB' : '—',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: _buildStatTile('Context', _formatContext(model.contextTokens))),
      ],
    );
  }

  Widget _buildStatTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          Text(value,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 4),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Colors.white54)),
        ],
      ),
    );
  }

  Widget _buildInstallSection() {
    if (!widget.runsInApp || widget.source == null) {
      return const SizedBox.shrink();
    }

    final snapshot = _downloadSnapshot;
    final isDownloading = snapshot != null && snapshot.isRunning;
    final failed = snapshot != null && snapshot.stage == ModelDownloadTaskStage.failed;
    final installed = _cacheEntry != null && !isDownloading;

    String statusText;
    Color statusColor;
    if (_checkingCache) {
      statusText = 'Checking install status…';
      statusColor = Colors.white54;
    } else if (isDownloading) {
      final pct = snapshot.fraction;
      statusText = pct != null ? 'Downloading… ${(pct * 100).toStringAsFixed(0)}%' : 'Downloading…';
      statusColor = Colors.deepPurple.shade200;
    } else if (failed) {
      statusText = snapshot.errorMessage ?? 'Download failed';
      statusColor = Colors.redAccent;
    } else if (installed) {
      statusText = 'Installed on this device';
      statusColor = Colors.greenAccent.shade200;
    } else {
      statusText = 'Not installed';
      statusColor = Colors.white54;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.download_for_offline_outlined, size: 16, color: Colors.deepPurple.shade200),
                const SizedBox(width: 8),
                const Text('On-device install',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white70)),
              ],
            ),
            const SizedBox(height: 10),
            Text(statusText, style: TextStyle(fontSize: 13, color: statusColor)),
            if (isDownloading) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: snapshot.fraction,
                  minHeight: 6,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation(Colors.deepPurple.shade200),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (_checkingCache)
              const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (isDownloading)
              OutlinedButton.icon(
                onPressed: _cancelDownload,
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Cancel download'),
              )
            else if (installed)
              OutlinedButton.icon(
                onPressed: _delete,
                style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Delete & uninstall'),
              )
            else
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: cardColor,
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: borderColor),
                ),
                onPressed: _download,
                icon: const Icon(Icons.download_outlined, size: 16),
                label: Text(failed ? 'Retry download' : 'Download & install'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerInstallSection() {
    if (!_isServerModel) return const SizedBox.shrink();

    final status = _serverCacheStatus;
    final installed = status?.cached ?? false;

    String statusText;
    Color statusColor;
    if (_checkingServerCache) {
      statusText = 'Checking install status…';
      statusColor = Colors.white54;
    } else if (_serverBusy) {
      statusText = installed ? 'Removing…' : 'Downloading… this can take a while for large models';
      statusColor = Colors.deepPurple.shade200;
    } else if (_serverError != null) {
      statusText = _serverError!;
      statusColor = Colors.redAccent;
    } else if (installed) {
      final sizeBytes = status?.sizeBytes;
      final sizeGb = sizeBytes != null ? sizeBytes / (1024 * 1024 * 1024) : null;
      statusText = sizeGb != null
          ? 'Cached on the backend machine (~${sizeGb.toStringAsFixed(sizeGb < 1 ? 2 : 1)} GB)'
          : 'Cached on the backend machine';
      statusColor = Colors.greenAccent.shade200;
    } else {
      statusText = 'Not downloaded yet';
      statusColor = Colors.white54;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.dns_outlined, size: 16, color: Colors.deepPurple.shade200),
                const SizedBox(width: 8),
                const Text('Backend install',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white70)),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Weights also download automatically on first chat — this just lets you '
              'manage them ahead of time.',
              style: TextStyle(fontSize: 11, color: Colors.white38),
            ),
            const SizedBox(height: 10),
            Text(statusText, style: TextStyle(fontSize: 13, color: statusColor)),
            const SizedBox(height: 12),
            if (_checkingServerCache || _serverBusy)
              const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (installed)
              OutlinedButton.icon(
                onPressed: _deleteServer,
                style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Delete & uninstall'),
              )
            else
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: cardColor,
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: borderColor),
                ),
                onPressed: _downloadServer,
                icon: const Icon(Icons.download_outlined, size: 16),
                label: Text(_serverError != null ? 'Retry download' : 'Download & install'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(IconData icon, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Colors.deepPurple.shade200),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white70)),
            ],
          ),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(fontSize: 14, color: Colors.white, height: 1.5)),
        ],
      ),
    );
  }
}
