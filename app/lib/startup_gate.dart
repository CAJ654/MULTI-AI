// What the app does between launch and the chat screen appearing.
//
// In development this is nearly a no-op — there is no bundled backend, so the
// gate falls straight through to [ChatScreen] and the developer's own server
// (or no server, for the on-device models) behaves as it always has.
//
// In a packaged build it has to cover the case a downloader actually hits: a
// clean machine with no Python, no dependencies, and no idea any of that is
// involved. That means a ~2.5GB pip install on first launch. Doing that behind
// a spinner would look like a hang for ten minutes, so it gets a real screen
// with pip's own output visible — a slow install that is visibly doing
// something reads very differently from a frozen window.

import 'package:flutter/material.dart';

import 'backend_process.dart';
import 'chat_screen.dart';
import 'update_service.dart';

enum _Phase { checking, needsSetup, provisioning, starting, ready, failed }

class StartupGate extends StatefulWidget {
  const StartupGate({super.key});

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> with WidgetsBindingObserver {
  final _supervisor = BackendSupervisor();
  final _log = <ProvisionProgress>[];
  final _logScroll = ScrollController();

  _Phase _phase = _Phase.checking;
  String _error = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _begin();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Best-effort: the backend is a child process, so it dies with the app on
    // a hard kill anyway, but a clean shutdown frees the GPU immediately
    // rather than whenever Windows gets round to it.
    _supervisor.stop();
    _logScroll.dispose();
    super.dispose();
  }

  Future<void> _begin() async {
    if (!BackendRuntime.isBundled) {
      // Development, or a non-Windows build: nothing to supervise.
      setState(() => _phase = _Phase.ready);
      return;
    }
    // Same guard, for the same reason: only a packaged build is a Velopack
    // install with anything to update. Deliberately not awaited — the check is
    // a network round trip and possibly a download, and none of that belongs
    // between launch and a usable app. It surfaces later, or never, as a
    // banner on the chat screen. See update_service.dart.
    UpdateService.instance.checkNow();
    if (!BackendRuntime.isProvisioned) {
      setState(() => _phase = _Phase.needsSetup);
      return;
    }
    await _startBackend();
  }

  Future<void> _startBackend() async {
    setState(() => _phase = _Phase.starting);
    try {
      await _supervisor.start();
      if (mounted) setState(() => _phase = _Phase.ready);
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.failed;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _runProvisioning() async {
    setState(() {
      _phase = _Phase.provisioning;
      _log.clear();
    });
    try {
      await for (final progress in provision()) {
        if (!mounted) return;
        setState(() {
          _log.add(progress);
          // The full pip transcript is thousands of lines and all that matters
          // is the tail, so the buffer is bounded rather than unbounded.
          if (_log.length > 200) _log.removeAt(0);
        });
        _scrollLogToEnd();
      }
      await _startBackend();
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.failed;
          _error = '$e';
        });
      }
    }
  }

  void _scrollLogToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) {
        _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_phase == _Phase.ready) return const ChatScreen();
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: switch (_phase) {
              _Phase.checking => const _Busy('Starting up…'),
              _Phase.starting => const _Busy('Starting the AI backend…'),
              _Phase.needsSetup => _buildWelcome(context),
              _Phase.provisioning => _buildProvisioning(context),
              _Phase.failed => _buildFailure(context),
              _Phase.ready => const SizedBox.shrink(),
            },
          ),
        ),
      ),
    );
  }

  Widget _buildWelcome(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('One-time setup', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 16),
        Text(
          'Multi-AI needs to download its AI runtime before first use — '
          'about 2.5 GB. This happens once; later launches start immediately.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Text(
          'You can skip this and still use the on-device models, which run '
          'without the backend. The larger server-backed models will be '
          'unavailable until setup finishes.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            FilledButton(
              onPressed: _runProvisioning,
              child: const Text('Download and install'),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: () => setState(() => _phase = _Phase.ready),
              child: const Text('Skip for now'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProvisioning(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Downloading AI runtime…', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'This takes several minutes on a typical connection. '
          'You can leave this window open in the background.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 20),
        const LinearProgressIndicator(),
        const SizedBox(height: 20),
        Container(
          height: 220,
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListView.builder(
            controller: _logScroll,
            itemCount: _log.length,
            itemBuilder: (context, i) => Text(
              _log[i].line,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: _log[i].isError ? theme.colorScheme.error : null,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFailure(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Setup did not finish', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 240),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              _error,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            FilledButton(
              onPressed: _runProvisioning,
              child: const Text('Try again'),
            ),
            const SizedBox(width: 12),
            // Not a dead end: the on-device models need none of this, so a
            // failed backend install should cost the server models, not the
            // whole app.
            TextButton(
              onPressed: () => setState(() => _phase = _Phase.ready),
              child: const Text('Continue without it'),
            ),
          ],
        ),
      ],
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 20),
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}
