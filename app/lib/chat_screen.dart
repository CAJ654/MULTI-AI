import 'package:flutter/material.dart';

import 'api_client.dart';
import 'chat_store.dart';
import 'model_detail_screen.dart';
import 'on_device_engine.dart';
import 'theme.dart';

class _Suggestion {
  const _Suggestion(this.title, this.subtitle);

  final String title;
  final String subtitle;

  String get prompt => '$title $subtitle';
}

const _suggestions = [
  _Suggestion('Tell me a fun fact', 'about the Roman Empire'),
  _Suggestion('Show me a code snippet', "of a website's sticky header"),
  _Suggestion('Help me study', 'vocabulary for a college entrance exam'),
  _Suggestion('Give me ideas', "for what to do with my kids' art"),
];

enum _SidebarTab { models, chat }

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, ApiClient? apiClient}) : _apiClient = apiClient;

  // Injectable so widget tests can supply a fake instead of hitting the
  // network; production code leaves this null and gets a real ApiClient.
  final ApiClient? _apiClient;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ApiClient _api = widget._apiClient ?? ApiClient();
  final _onDeviceEngine = OnDeviceEngine();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _store = ChatStore();

  final _sessions = <ChatSession>[ChatSession()];
  int _activeSession = 0;
  _SidebarTab _sidebarTab = _SidebarTab.chat;

  List<ModelInfo> _models = [];
  ModelInfo? _selectedModel;
  String? _loadError;
  bool _loadingModels = true;
  bool _sending = false;
  bool _showScrollToBottom = false;

  // Bumped on every send and on stop; a reply whose generation no longer
  // matches was stopped by the user and gets discarded on arrival.
  int _sendGeneration = 0;
  ChatSession? _pendingSession;

  ChatSession get _session => _sessions[_activeSession];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadModels();
    _loadStoredSessions();
  }

  Future<void> _loadStoredSessions() async {
    final stored = await _store.load();
    if (!mounted || stored.isEmpty) return;
    setState(() {
      // Keep the fresh empty session on top and resume with history below it.
      _sessions.addAll(stored);
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    // Show the "jump to bottom" button once the user has scrolled up more than
    // a screenful's worth away from the newest message.
    final distanceFromBottom =
        _scrollController.position.maxScrollExtent - _scrollController.offset;
    final show = distanceFromBottom > 120;
    if (show != _showScrollToBottom) {
      setState(() => _showScrollToBottom = show);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _onDeviceEngine.dispose();
    super.dispose();
  }

  Future<void> _loadModels() async {
    setState(() {
      _loadingModels = true;
      _loadError = null;
    });
    // The on-device model needs no server, so it's always available even if
    // the backend below can't be reached.
    const onDeviceModel = ModelInfo(
      id: onDeviceModelId,
      name: onDeviceModelName,
      params: onDeviceModelParams,
      sizeGb: onDeviceModelSizeGb,
      modality: onDeviceModelModality,
      contextTokens: onDeviceModelContextTokens,
      license: onDeviceModelLicense,
      strengths: onDeviceModelStrengths,
      speedProfile: onDeviceModelSpeedProfile,
    );
    try {
      final serverModels = await _api.fetchModels();
      setState(() => _models = [onDeviceModel, ...serverModels]);
    } catch (e) {
      setState(() {
        _models = [onDeviceModel];
        _loadError = 'Backend unreachable — only the on-device model is available.';
      });
    } finally {
      setState(() {
        _selectedModel = _models.isNotEmpty ? _models.first : null;
        _loadingModels = false;
      });
    }
  }

  void _newSession() {
    // Reuse an existing empty session (they're hidden from the sidebar, so
    // stacking up duplicates would leak invisible entries).
    final existing = _sessions.indexWhere((s) => s.messages.isEmpty);
    setState(() {
      if (existing >= 0) {
        _activeSession = existing;
      } else {
        _sessions.insert(0, ChatSession());
        _activeSession = 0;
      }
    });
  }

  void _deleteSession(int index) {
    setState(() {
      _sessions.removeAt(index);
      if (_sessions.isEmpty) _sessions.add(ChatSession());
      if (_activeSession >= _sessions.length) {
        _activeSession = _sessions.length - 1;
      } else if (index < _activeSession) {
        _activeSession -= 1;
      }
    });
    _store.save(_sessions);
  }

  Future<void> _showSessionMenu(Offset position, int index) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<String>(
      context: context,
      color: cardColor,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
              SizedBox(width: 10),
              Text('Delete', style: TextStyle(color: Colors.redAccent)),
            ],
          ),
        ),
      ],
    );
    if (action == 'delete') _deleteSession(index);
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _controller.text).trim();
    final model = _selectedModel;
    if (text.isEmpty || model == null || _sending) return;

    final session = _session;
    final generation = ++_sendGeneration;
    _pendingSession = session;
    setState(() {
      session.title ??= text;
      session.messages.add(ChatMessage(text: text, isUser: true));
      _sending = true;
    });
    _controller.clear();
    _scrollToBottom();
    _store.save(_sessions);

    try {
      // Models with a GGUF source run locally via llama.cpp; the rest go to
      // the Python backend.
      final localSource = model.id == onDeviceModelId ? onDeviceModelSource : model.gguf;
      final reply = localSource != null
          ? await _onDeviceEngine.generate(text, source: localSource)
          : await _api.sendChat(model: model.id, message: text);
      if (generation != _sendGeneration) return; // stopped by the user
      setState(() => session.messages.add(ChatMessage(text: reply, isUser: false, sender: model.name)));
    } catch (e) {
      if (generation != _sendGeneration) return; // aborting throws; not a real error
      setState(() =>
          session.messages.add(ChatMessage(text: e.toString(), isUser: false, sender: model.name, isError: true)));
    } finally {
      if (generation == _sendGeneration) {
        _pendingSession = null;
        setState(() => _sending = false);
        _scrollToBottom();
      }
      _store.save(_sessions);
    }
  }

  void _stopResponse() {
    if (!_sending) return;
    _sendGeneration++; // orphan the in-flight request so its reply is discarded
    _api.cancelChat();
    _onDeviceEngine.stop();
    final session = _pendingSession;
    _pendingSession = null;
    setState(() {
      _sending = false;
      session?.messages.add(ChatMessage(
          text: '(response stopped)', isUser: false, sender: _selectedModel?.name));
    });
    _store.save(_sessions);
  }

  void _scrollToBottom({bool animate = true}) {
    // A newly added message may still be laying out (long text measures its
    // height after the current frame), so maxScrollExtent grows across a couple
    // of frames. Re-jump on the next frame until we're actually at the bottom.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animate) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(target);
      }
      // Second pass after layout settles, in case the content got taller.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        final settled = _scrollController.position.maxScrollExtent;
        if ((settled - _scrollController.offset).abs() > 1) {
          _scrollController.jumpTo(settled);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: mainColor,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSidebar(),
          Expanded(
            child: Column(
              children: [
                _buildTopBar(),
                if (_loadError != null) _buildWarningBanner(),
                Expanded(child: _buildBody()),
                if (!_loadingModels && _models.isNotEmpty) _buildInputArea(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- sidebar

  Widget _buildSidebar() {
    return Container(
      width: 280,
      color: sidebarColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, size: 20, color: Colors.deepPurple.shade200),
                const SizedBox(width: 10),
                const Text('Multi-AI',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
              ],
            ),
          ),
          _buildSidebarTabBar(),
          const SizedBox(height: 8),
          Expanded(
            child: _sidebarTab == _SidebarTab.models ? _buildModelsTab() : _buildChatTab(),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarTabBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(child: _buildSidebarTabButton('Models', _SidebarTab.models)),
          const SizedBox(width: 8),
          Expanded(child: _buildSidebarTabButton('Chat', _SidebarTab.chat)),
        ],
      ),
    );
  }

  Widget _buildSidebarTabButton(String label, _SidebarTab tab) {
    final selected = _sidebarTab == tab;
    return Material(
      color: selected ? cardColor : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _sidebarTab = tab),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : Colors.white54,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: cardColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _newSession,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New Chat'),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Builder(builder: (context) {
            // A chat only appears here once it has a message; a freshly
            // opened (still empty) chat stays hidden.
            final visible = [
              for (var i = 0; i < _sessions.length; i++)
                if (_sessions[i].messages.isNotEmpty) i,
            ];
            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: visible.length,
              itemBuilder: (context, i) {
                final index = visible[i];
                final s = _sessions[index];
                final selected = index == _activeSession;
                return GestureDetector(
                  // Right-click (or long-press on touch) opens the chat's
                  // context menu with Delete.
                  onSecondaryTapUp: (details) =>
                      _showSessionMenu(details.globalPosition, index),
                  child: Material(
                    color: selected ? cardColor : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    child: ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      leading: const Icon(Icons.chat_bubble_outline, size: 16, color: Colors.white54),
                      title: Text(
                        s.title ?? 'New chat',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: selected ? Colors.white : Colors.white70),
                      ),
                      onTap: () => setState(() => _activeSession = index),
                      onLongPress: () {
                        final box = context.findRenderObject() as RenderBox?;
                        final origin = box?.localToGlobal(Offset.zero) ?? Offset.zero;
                        _showSessionMenu(origin, index);
                      },
                    ),
                  ),
                );
              },
            );
          }),
        ),
      ],
    );
  }

  // ----------------------------------------------------------------- models tab

  Widget _buildModelsTab() {
    if (_loadingModels) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_models.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('No models available', style: TextStyle(color: Colors.white54)),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemCount: _models.length,
      itemBuilder: (context, i) => _buildModelCard(_models[i]),
    );
  }

  Widget _buildModelCard(ModelInfo m) {
    // Everything here runs locally on this machine — there's no cloud call
    // anywhere in this app. The distinction is *how*: in-app via llama.cpp
    // (llamadart) vs. via the local Python backend process (transformers).
    final inApp = m.id == onDeviceModelId || m.gguf != null;
    final details = [
      if (m.params != null) '${m.params} params',
      if (m.sizeGb != null) '~${m.sizeGb!.toStringAsFixed(m.sizeGb! < 1 ? 2 : 1)} GB',
    ].join(' • ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ModelDetailScreen(model: m, runsInApp: inApp),
          )),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(inApp ? Icons.smartphone_outlined : Icons.dns_outlined,
                    size: 18, color: Colors.deepPurple.shade200),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.name,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                      if (details.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(details, style: const TextStyle(fontSize: 12, color: Colors.white54)),
                      ],
                      const SizedBox(height: 2),
                      Text(inApp ? 'In-app (llama.cpp)' : 'Local backend (Python)',
                          style: const TextStyle(fontSize: 11, color: Colors.white38)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18, color: Colors.white24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------------- top bar

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: borderColor))),
      child: Row(
        children: [
          if (_loadingModels)
            const Text('Loading models…', style: TextStyle(color: Colors.white54))
          else if (_models.isNotEmpty)
            DropdownButtonHideUnderline(
              child: DropdownButton<ModelInfo>(
                value: _selectedModel,
                dropdownColor: cardColor,
                borderRadius: BorderRadius.circular(12),
                icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white54),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                items: _models
                    .map((m) => DropdownMenuItem(value: m, child: Text(m.name)))
                    .toList(),
                onChanged: _sending ? null : (m) => setState(() => _selectedModel = m),
              ),
            ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildWarningBanner() {
    return Container(
      width: double.infinity,
      color: const Color(0xFF3A2E14),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(child: Text(_loadError!, style: const TextStyle(fontSize: 13, color: Colors.amber))),
          TextButton(onPressed: _loadModels, child: const Text('Retry')),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------- body

  Widget _buildBody() {
    if (_loadingModels) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_models.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('No models available: $_loadError',
                style: TextStyle(color: Colors.red.shade300)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadModels, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_session.messages.isEmpty) {
      return _buildEmptyState();
    }
    return Stack(
      children: [
        Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView.builder(
              controller: _scrollController,
              // Generous bottom padding so the last message clears the input
              // bar with room to spare instead of sitting flush against it.
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 48),
              itemCount: _session.messages.length + (_sending ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _session.messages.length) return _buildThinkingRow();
                return _buildMessageRow(_session.messages[index]);
              },
            ),
          ),
        ),
        if (_showScrollToBottom)
          Positioned(
            right: 24,
            bottom: 16,
            child: FloatingActionButton.small(
              backgroundColor: cardColor,
              foregroundColor: Colors.white,
              elevation: 2,
              onPressed: () => _scrollToBottom(),
              child: const Icon(Icons.arrow_downward, size: 20),
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome, size: 48, color: Colors.deepPurple.shade200),
              const SizedBox(height: 20),
              const Text(
                'How can I help you today?',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              const SizedBox(height: 36),
              LayoutBuilder(
                builder: (context, constraints) {
                  final twoColumns = constraints.maxWidth > 520;
                  final cardWidth =
                      twoColumns ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: _suggestions
                        .map((s) => SizedBox(width: cardWidth, child: _buildSuggestionCard(s)))
                        .toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionCard(_Suggestion s) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _sending ? null : () => _send(s.prompt),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: borderColor),
            color: cardColor.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.title,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
              const SizedBox(height: 4),
              Text(s.subtitle, style: const TextStyle(fontSize: 13, color: Colors.white54)),
            ],
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------- messages

  Widget _buildMessageRow(ChatMessage message) {
    if (message.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.deepPurple.shade400,
            borderRadius: BorderRadius.circular(18),
          ),
          child: SelectableText(message.text,
              style: const TextStyle(color: Colors.white, height: 1.4)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAvatar(message.isError),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message.sender ?? 'Assistant',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white70)),
                const SizedBox(height: 4),
                SelectableText(
                  message.text,
                  style: TextStyle(
                    height: 1.5,
                    color: message.isError ? Colors.red.shade300 : Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThinkingRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAvatar(false),
          const SizedBox(width: 12),
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Row(
              children: [
                SizedBox(
                    width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 10),
                Text('Thinking… (first use of a model downloads its weights)',
                    style: TextStyle(fontSize: 13, color: Colors.white54)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(bool isError) {
    return CircleAvatar(
      radius: 15,
      backgroundColor: isError ? const Color(0xFF3A1B1B) : Colors.deepPurple.shade700,
      child: Icon(isError ? Icons.error_outline : Icons.auto_awesome,
          size: 15, color: Colors.white),
    );
  }

  // ------------------------------------------------------------------ input

  Widget _buildInputArea() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 14),
      child: Column(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Container(
              padding: const EdgeInsets.only(left: 20, right: 8),
              decoration: BoxDecoration(
                color: cardColor,
                border: Border.all(color: borderColor),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: !_sending,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Send a message',
                        hintStyle: TextStyle(color: Colors.white38),
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.deepPurple.shade400,
                        disabledBackgroundColor: Colors.white10,
                      ),
                      tooltip: _sending ? 'Stop response' : 'Send',
                      icon: Icon(_sending ? Icons.stop_rounded : Icons.arrow_upward,
                          size: 20, color: Colors.white),
                      onPressed: _sending ? _stopResponse : _send,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'LLMs can make mistakes. Verify important information.',
            style: TextStyle(fontSize: 12, color: Colors.white38),
          ),
        ],
      ),
    );
  }
}
