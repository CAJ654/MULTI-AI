import 'package:flutter/material.dart';

import '../../backend_process.dart' show ProvisionProgress;
import '../../theme.dart';
import 'component.dart';
import 'component_manager.dart';

/// Full-page install/delete flow for one component, pushed when its card is
/// tapped in the Add-ons tab's sidebar. Structurally follows
/// `model_detail_screen.dart`'s `_buildServerInstallSection` — "install into
/// a backend-managed cache via an async op with a checking/installing/
/// installed/failed state machine and a delete confirmation" — since that's
/// closer to what a component install actually is than the chunked on-device
/// GGUF download path is.
class ComponentDetailScreen extends StatefulWidget {
  const ComponentDetailScreen({super.key, required this.component, required this.manager});

  final LocalComponent component;
  final ComponentManager manager;

  @override
  State<ComponentDetailScreen> createState() => _ComponentDetailScreenState();
}

class _ComponentDetailScreenState extends State<ComponentDetailScreen> {
  bool _busy = false;
  String? _statusLine;
  String? _error;

  LocalComponent get _component => widget.component;
  ComponentManager get _manager => widget.manager;

  Future<void> _install() async {
    setState(() {
      _busy = true;
      _error = null;
      _statusLine = 'Starting install…';
    });
    try {
      await for (final ProvisionProgress progress in _manager.install(_component)) {
        if (!mounted) return;
        // Only the latest line is shown — this is a status readout, not a
        // scrolling log, matching how StorageSettingsDialog and the server
        // model install section in model_detail_screen.dart both surface pip
        // output: enough to show it's alive, not a terminal transcript.
        setState(() {
          if (progress.isError) {
            _error = progress.line;
          } else {
            _statusLine = progress.line;
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardColor,
        title: const Text('Delete & uninstall?', style: TextStyle(color: Colors.white)),
        content: Text(
          'This removes ${_component.name} from this device'
          '${_component.kind == ComponentKind.server ? ' and stops it if running' : ''}. '
          "Anything that uses it — like Chat's web search toggle — will ask you to "
          'reinstall it from here first.',
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
      _busy = true;
      _error = null;
    });
    try {
      await _manager.uninstall(_component);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _manager,
      builder: (context, _) {
        final installed = _manager.isInstalled(_component.id);
        return Scaffold(
          backgroundColor: mainColor,
          appBar: AppBar(
            backgroundColor: mainColor,
            elevation: 0,
            title: Text(_component.name),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_component.description,
                        style: const TextStyle(fontSize: 14, color: Colors.white, height: 1.5)),
                    const SizedBox(height: 20),
                    _buildInstallSection(installed),
                    if (_component.id == 'searxng') ...[
                      const SizedBox(height: 20),
                      _buildSearxngDisclosure(),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInstallSection(bool installed) {
    String statusText;
    Color statusColor;
    if (_busy) {
      statusText = _statusLine ?? (installed ? 'Working…' : 'Installing…');
      statusColor = Colors.deepPurple.shade200;
    } else if (_error != null) {
      statusText = _error!;
      statusColor = Colors.redAccent;
    } else if (installed) {
      statusText = '~${_component.approxInstalledMb} MB installed on this device';
      statusColor = Colors.greenAccent.shade200;
    } else {
      statusText = 'Not installed — about ~${_component.approxInstalledMb} MB to download';
      statusColor = Colors.white54;
    }

    return Container(
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
              const Text('Install',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white70)),
            ],
          ),
          const SizedBox(height: 10),
          Text(statusText, style: TextStyle(fontSize: 13, color: statusColor)),
          if (_busy) ...[
            const SizedBox(height: 10),
            const ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(4)),
              child: LinearProgressIndicator(minHeight: 6, backgroundColor: Colors.white12),
            ),
          ],
          const SizedBox(height: 12),
          if (_busy)
            const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
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
              onPressed: _install,
              icon: const Icon(Icons.download_outlined, size: 16),
              label: Text(_error != null ? 'Retry install' : 'Install'),
            ),
        ],
      ),
    );
  }

  /// Honest disclosure about what "local" does and doesn't mean here — shown
  /// right where the user decides to install, the same place
  /// `model_detail_screen.dart`'s `_buildExternalEndpointSection` is upfront
  /// about the Colibri caveat.
  Widget _buildSearxngDisclosure() {
    return Container(
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
              Icon(Icons.info_outline, size: 16, color: Colors.deepPurple.shade200),
              const SizedBox(width: 8),
              const Text('What this actually does',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white70)),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'SearXNG runs entirely on this machine and needs no account or API key. '
            "It's still not the same as staying fully offline: to answer a search it "
            'relays your query to engines like Bing and DuckDuckGo over the open '
            'internet, the same as if you visited them yourself — those engines see '
            'the query and your IP address.',
            style: TextStyle(fontSize: 12, height: 1.5, color: Colors.white70),
          ),
          const SizedBox(height: 10),
          const Text(
            'Relaying scraped-style search requests to those engines is a widely used '
            "but not formally sanctioned pattern — this is a known community gray "
            "area, not a compliance guarantee.",
            style: TextStyle(fontSize: 12, height: 1.5, color: Colors.white54),
          ),
        ],
      ),
    );
  }
}
