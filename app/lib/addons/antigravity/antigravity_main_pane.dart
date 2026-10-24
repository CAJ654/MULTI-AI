import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api_client.dart' show ModelInfo;
import '../../copy_button.dart';
import '../../theme.dart';
import '../chat/chat_controller.dart' show modelDisplayName;
import 'antigravity_controller.dart';
import 'local_model_server.dart';

/// The Antigravity tab: start/stop the local endpoint, copy its URL and
/// token, and read what it can and can't do. See `local_model_server.dart` for
/// the endpoint itself.
class AntigravityMainPane extends StatefulWidget {
  const AntigravityMainPane({super.key, required this.controller});

  final AntigravityController controller;

  @override
  State<AntigravityMainPane> createState() => _AntigravityMainPaneState();
}

class _AntigravityMainPaneState extends State<AntigravityMainPane> {
  late final TextEditingController _portController;
  bool _showToken = false;

  @override
  void initState() {
    super.initState();
    _portController = TextEditingController(text: '${widget.controller.settings.port}');
    widget.controller.addListener(_syncPort);
  }

  /// The settings load from disk after the pane is built, so the field has to
  /// pick the saved port up when it arrives — but never overwrite what the
  /// user is typing.
  void _syncPort() {
    final saved = '${widget.controller.settings.port}';
    if (!widget.controller.running && _portController.text != saved && !_portFocus.hasFocus) {
      _portController.text = saved;
    }
  }

  final _portFocus = FocusNode();

  @override
  void dispose() {
    widget.controller.removeListener(_syncPort);
    _portController.dispose();
    _portFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _experimentalBanner(),
                  const SizedBox(height: 16),
                  _serverCard(),
                  const SizedBox(height: 16),
                  _setupSection(),
                  const SizedBox(height: 16),
                  _limitationsSection(),
                  const SizedBox(height: 16),
                  _logSection(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _experimentalBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: fitPossibleColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: fitPossibleColor.withValues(alpha: 0.4)),
      ),
      child: const Text(
        'Experimental. Antigravity has no supported way to use outside models, '
        'so this only offers an OpenAI-compatible endpoint on this PC. While '
        "it's running, any program on this PC that has the token can use your "
        'models. Nothing leaves the machine.',
        style: TextStyle(fontSize: 12.5, height: 1.4, color: Colors.white70),
      ),
    );
  }

  Widget _serverCard() {
    final controller = widget.controller;
    final state = controller.state;
    final running = controller.running;
    final busy = state == AntigravityServerState.starting;
    final downloaded = controller.modelPool.downloaded;
    final defaultModel = controller.defaultModel;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.circle, size: 10, color: running ? fitOptimalColor : fitUnknownColor),
              const SizedBox(width: 8),
              Text(
                switch (state) {
                  AntigravityServerState.running => 'Running',
                  AntigravityServerState.starting => 'Starting…',
                  AntigravityServerState.error => 'Error',
                  AntigravityServerState.stopped => 'Stopped',
                },
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
              ),
              const Spacer(),
              FilledButton(
                onPressed: busy ? null : (running ? controller.stop : controller.start),
                child: Text(running ? 'Stop' : 'Start'),
              ),
            ],
          ),
          if (controller.error != null) ...[
            const SizedBox(height: 8),
            Text(controller.error!, style: const TextStyle(fontSize: 12.5, color: fitNotRecommendedColor)),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              const Text('Port', style: TextStyle(fontSize: 13, color: Colors.white70)),
              const SizedBox(width: 12),
              SizedBox(
                width: 90,
                child: TextField(
                  controller: _portController,
                  focusNode: _portFocus,
                  enabled: !running && !busy,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(fontSize: 13, color: Colors.white),
                  decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                  onSubmitted: (value) {
                    final port = int.tryParse(value);
                    if (port != null) {
                      controller.setPort(port);
                    }
                  },
                  onTapOutside: (_) {
                    final port = int.tryParse(_portController.text);
                    if (port != null) {
                      controller.setPort(port);
                    }
                    _portFocus.unfocus();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Default model', style: TextStyle(fontSize: 13, color: Colors.white70)),
              const SizedBox(width: 12),
              Expanded(
                child: downloaded.isEmpty
                    ? const Text('No models downloaded', style: TextStyle(fontSize: 13, color: Colors.white54))
                    : DropdownButtonHideUnderline(
                        child: DropdownButton<ModelInfo>(
                          value: defaultModel,
                          isExpanded: true,
                          dropdownColor: cardColor,
                          style: const TextStyle(fontSize: 13, color: Colors.white),
                          items: [
                            for (final m in downloaded)
                              DropdownMenuItem(
                                value: m,
                                child: Text(modelDisplayName(m), overflow: TextOverflow.ellipsis),
                              ),
                          ],
                          onChanged: (m) {
                            if (m != null) {
                              controller.selectModel(m);
                            }
                          },
                        ),
                      ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Used whenever a request names a model this app does not have, '
              'which is every request that comes through a proxy.',
              style: TextStyle(fontSize: 11.5, color: Colors.white38),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Start automatically', style: TextStyle(fontSize: 13, color: Colors.white70)),
            value: controller.settings.autoStart,
            onChanged: controller.setAutoStart,
          ),
        ],
      ),
    );
  }

  Widget _setupSection() {
    final controller = widget.controller;
    final token = controller.settings.bearerToken;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Connection details',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
          const SizedBox(height: 10),
          _valueRow('Base URL', controller.baseUrl, copy: controller.baseUrl),
          _valueRow(
            'API key',
            _showToken ? token : '•' * 24,
            copy: token,
            trailing: IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              tooltip: _showToken ? 'Hide' : 'Show',
              onPressed: () => setState(() => _showToken = !_showToken),
              icon: Icon(_showToken ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: Colors.white54),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: controller.regenerateToken,
              child: const Text('Generate a new key'),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Use these in any OpenAI-compatible client. For Antigravity:',
            style: TextStyle(fontSize: 12.5, height: 1.4, color: Colors.white70),
          ),
          const SizedBox(height: 6),
          const Text(
            'Antigravity cannot be pointed at a custom model directly. The '
            'community "antigravity-proxy" (github.com/12errh/antigravity-proxy) '
            "translates Antigravity 2.0's Gemini calls to OpenAI-style providers. "
            'Its README documents per-provider API keys and auto-discovery of '
            'local servers, but no custom base URL, so whether it can reach this '
            "endpoint is untested. Check its dashboard before relying on it. It "
            "also needs administrator rights and intercepts Antigravity's "
            'traffic on port 443, so read what it does before installing.',
            style: TextStyle(fontSize: 12, height: 1.45, color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _limitationsSection() {
    const items = [
      'No tool calling: tools in a request are ignored and replies are plain '
          "text, so Antigravity's agent features will not work.",
      'No token-by-token streaming: a streamed reply arrives in one piece once '
          'the model has finished.',
      'Small local models are weak at agent-style work, even with the above fixed.',
    ];
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Limitations',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
          const SizedBox(height: 8),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('•  $item',
                  style: const TextStyle(fontSize: 12.5, height: 1.4, color: Colors.white54)),
            ),
        ],
      ),
    );
  }

  Widget _logSection() {
    final log = widget.controller.log;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Recent requests',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
          const SizedBox(height: 8),
          if (log.isEmpty)
            const Text('Nothing yet.', style: TextStyle(fontSize: 12.5, color: Colors.white38))
          else
            for (final entry in log) _logRow(entry),
        ],
      ),
    );
  }

  Widget _logRow(ServerRequestLog entry) {
    final ok = entry.status >= 200 && entry.status < 300;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text('${entry.status}',
                style: TextStyle(fontSize: 12, color: ok ? fitOptimalColor : fitNotRecommendedColor)),
          ),
          Expanded(
            child: Text(
              '${entry.method} ${entry.path}${entry.modelId == null ? '' : '  ·  ${entry.modelId}'}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ),
          Text('${(entry.duration.inMilliseconds / 1000).toStringAsFixed(1)}s',
              style: const TextStyle(fontSize: 12, color: Colors.white38)),
        ],
      ),
    );
  }

  Widget _valueRow(String label, String value, {required String copy, Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(label, style: const TextStyle(fontSize: 13, color: Colors.white70)),
          ),
          Expanded(
            child: SelectableText(
              value,
              maxLines: 1,
              style: const TextStyle(fontSize: 12.5, fontFamily: 'Consolas', color: Colors.white),
            ),
          ),
          ?trailing,
          CopyButton(copy),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: child,
    );
  }
}
