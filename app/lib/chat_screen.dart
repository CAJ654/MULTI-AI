import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:llamadart/llamadart.dart' hide ChatSession;

import 'api_client.dart';
import 'attachment_input.dart';
import 'chat_store.dart';
import 'model_detail_screen.dart';
import 'on_device_engine.dart';
import 'theme.dart';
import 'thinking_indicator.dart';
import 'thinking_settings.dart';
import 'thinking_settings_dialog.dart';

class _Suggestion {
  const _Suggestion(this.title, this.subtitle);

  final String title;
  final String subtitle;

  String get prompt => '$title $subtitle';
}

// Shared pool the empty-state screen draws 4 suggestions from at random. Kept
// larger than any one screenful so repeat visits to "New Chat" don't always
// show the same four.
const _suggestionPool = [
  _Suggestion('Tell me a fun fact', 'about the Roman Empire'),
  _Suggestion('Show me a code snippet', "of a website's sticky header"),
  _Suggestion('Help me study', 'vocabulary for a college entrance exam'),
  _Suggestion('Give me ideas', "for what to do with my kids' art"),
  _Suggestion('Write a short story', 'about a lighthouse keeper'),
  _Suggestion('Explain a concept', 'like quantum entanglement, simply'),
  _Suggestion('Plan a trip', 'to Japan for two weeks'),
  _Suggestion('Debug my code', 'for a Python off-by-one error'),
  _Suggestion('Draft an email', 'declining a meeting politely'),
  _Suggestion('Suggest a recipe', "using what's in my fridge"),
  _Suggestion('Brainstorm names', 'for a new coffee shop'),
  _Suggestion('Summarize an article', 'on climate policy'),
  _Suggestion('Create a workout plan', 'for a beginner runner'),
  _Suggestion('Explain the math', 'behind compound interest'),
  _Suggestion('Give me a book recommendation', 'similar to Dune'),
  _Suggestion('Help me practice', 'for a job interview'),
];

const _suggestionCount = 4;

List<_Suggestion> _pickRandomSuggestions() {
  final pool = List<_Suggestion>.from(_suggestionPool)..shuffle(Random());
  return pool.take(_suggestionCount).toList();
}

enum _SidebarTab { models, chat, orchestration, code }

/// Chat UI model names always end in an explicit "(on-device)" / "(local
/// server)" tag so it's clear which one is answering — the raw name from
/// the backend isn't consistent about this (on-device sibling files bake in
/// "(On-Device)", but the built-in Qwen2.5 0.5B and gguf-only entries like
/// GPT-OSS don't have any suffix at all).
String _modelDisplayName(ModelInfo m) {
  final inApp = m.id == onDeviceModelId || m.gguf != null;
  const rawSuffix = ' (On-Device)';
  var base = m.name;
  if (base.endsWith(rawSuffix)) {
    base = base.substring(0, base.length - rawSuffix.length);
  }
  return inApp ? '$base (on-device)' : '$base (local server)';
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    ApiClient? apiClient,
    ModelDownloadManager? downloadManager,
    AttachmentSource? attachmentSource,
  })  : _apiClient = apiClient,
        _downloadManager = downloadManager,
        _attachmentSource = attachmentSource;

  // Injectable so widget tests can supply a fake instead of hitting the
  // network; production code leaves this null and gets a real ApiClient.
  final ApiClient? _apiClient;

  // Injectable so widget tests can supply a fake instead of touching the
  // real on-device model cache directory; production code leaves this null
  // and gets a real DefaultModelDownloadManager.
  final ModelDownloadManager? _downloadManager;

  // Injectable so widget tests can drive the attach/mic buttons without
  // opening a real file dialog or recording from a real microphone.
  final AttachmentSource? _attachmentSource;

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

  final _thinkingSettingsStore = ThinkingSettingsStore();
  ThinkingSettings _thinkingSettings = ThinkingSettings.defaults();

  late final ModelDownloadManager _downloadManager =
      widget._downloadManager ?? DefaultModelDownloadManager();
  late final AttachmentSource _attachments =
      widget._attachmentSource ?? DefaultAttachmentSource();

  /// Staged for the next send, cleared once it goes out. Rendered as a strip
  /// of thumbnails/chips above the text field.
  final _pendingAttachments = <Attachment>[];
  bool _recording = false;

  List<ModelInfo> _models = [];
  // Ids of models whose weights are actually present — on-device cache hit,
  // or the backend's HF cache reports one. The chat picker only offers these:
  // selecting an undownloaded model would otherwise silently kick off a
  // multi-GB download on first send. The Models tab still shows everything.
  Set<String> _downloadedModelIds = {};
  bool _checkingDownloads = true;
  ModelInfo? _selectedModel;
  String? _loadError;
  bool _loadingModels = true;
  bool _sending = false;
  bool _showScrollToBottom = false;

  List<ModelInfo> get _downloadedModels =>
      _models.where((m) => _downloadedModelIds.contains(m.id)).toList();

  // Bumped on every send and on stop; a reply whose generation no longer
  // matches was stopped by the user and gets discarded on arrival.
  int _sendGeneration = 0;
  ChatSession? _pendingSession;

  ChatSession get _session => _sessions[_activeSession];

  // Suggestions are randomized once per session and cached here, so they stay
  // put across rebuilds (typing, dialogs closing, etc.) but reshuffle whenever
  // a genuinely new chat screen is shown.
  final _sessionSuggestions = <ChatSession, List<_Suggestion>>{};

  List<_Suggestion> _suggestionsFor(ChatSession session) =>
      _sessionSuggestions.putIfAbsent(session, _pickRandomSuggestions);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadModels();
    _loadStoredSessions();
    _loadThinkingSettings();
  }

  Future<void> _loadThinkingSettings() async {
    final settings = await _thinkingSettingsStore.load();
    if (!mounted) return;
    setState(() => _thinkingSettings = settings);
  }

  void _openThinkingSettings() {
    showDialog<void>(
      context: context,
      builder: (_) => ThinkingSettingsDialog(
        initial: _thinkingSettings,
        onChanged: (settings) {
          setState(() => _thinkingSettings = settings);
          _thinkingSettingsStore.save(settings);
        },
      ),
    );
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
    _attachments.dispose();
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
      available: true,
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
      setState(() => _loadingModels = false);
    }
    await _refreshDownloadedModels();
  }

  Future<bool> _isModelDownloaded(ModelInfo m) async {
    if (!m.available) return false;
    final source = m.id == onDeviceModelId ? onDeviceModelSource : m.gguf;
    if (source != null) {
      final entry = await _downloadManager.get(ModelSource.parse(source).cacheKey);
      if (entry == null) return false;
      // A vision model whose projector is missing would load and chat but
      // silently fail to see, after the + button had already been offered —
      // so it doesn't count as downloaded until both files are present.
      final mmproj = m.mmproj;
      if (mmproj != null) {
        return await _downloadManager.get(ModelSource.parse(mmproj).cacheKey) != null;
      }
      return true;
    }
    try {
      final status = await _api.getServerModelCacheStatus(m.id);
      return status.cached;
    } catch (_) {
      return false;
    }
  }

  /// Re-checks which models are actually downloaded — called after models
  /// load and again whenever the user returns from a model's detail page
  /// (where downloads/deletes happen), so the chat picker stays in sync.
  Future<void> _refreshDownloadedModels() async {
    setState(() => _checkingDownloads = true);
    final models = _models;
    final flags = await Future.wait(models.map(_isModelDownloaded));
    if (!mounted) return;
    final downloadedIds = {
      for (var i = 0; i < models.length; i++)
        if (flags[i]) models[i].id,
    };
    setState(() {
      _downloadedModelIds = downloadedIds;
      _checkingDownloads = false;
      if (_selectedModel == null || !downloadedIds.contains(_selectedModel!.id)) {
        final downloaded = models.where((m) => downloadedIds.contains(m.id));
        _selectedModel = downloaded.isNotEmpty ? downloaded.first : null;
      }
    });
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
      _sessionSuggestions.remove(_sessions[index]);
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
    // Attachments are only staged while a model that accepts them is picked,
    // but the picker can change between staging and sending — drop anything
    // the current model can't take rather than having the backend reject it.
    final attachments = _usableAttachments(model);
    if (model == null || _sending) return;
    // An attachment alone is a valid message ("what's in this picture?" is
    // implied); text alone still isn't when there's nothing attached.
    if (text.isEmpty && attachments.isEmpty) return;

    final session = _session;
    final generation = ++_sendGeneration;
    _pendingSession = session;
    setState(() {
      session.title ??= text.isEmpty ? _attachmentSummary(attachments) : text;
      session.messages
          .add(ChatMessage(text: text, isUser: true, attachments: attachments));
      _pendingAttachments.clear();
      _sending = true;
    });
    _controller.clear();
    _scrollToBottom();
    _store.save(_sessions);

    try {
      // Models with a GGUF source run locally via llama.cpp; the rest go to
      // the Python backend.
      final localSource = model.id == onDeviceModelId ? onDeviceModelSource : model.gguf;
      final localSizeGb = model.id == onDeviceModelId ? onDeviceModelSizeGb : model.sizeGb;
      final reply = localSource != null
          ? await _onDeviceEngine.generate(
              text,
              source: localSource,
              sizeGb: localSizeGb,
              mmproj: model.mmproj,
              attachments: attachments,
            )
          : await _api.sendChat(model: model.id, message: text, attachments: attachments);
      if (generation != _sendGeneration) return; // stopped by the user
      setState(() => session.messages
          .add(ChatMessage(text: reply, isUser: false, sender: _modelDisplayName(model))));
    } catch (e) {
      if (generation != _sendGeneration) return; // aborting throws; not a real error
      setState(() => session.messages.add(
          ChatMessage(text: e.toString(), isUser: false, sender: _modelDisplayName(model), isError: true)));
    } finally {
      if (generation == _sendGeneration) {
        _pendingSession = null;
        setState(() => _sending = false);
        _scrollToBottom();
      }
      _store.save(_sessions);
    }
  }

  // ------------------------------------------------------------ attachments

  /// The staged attachments [model] can actually accept. Empty for a
  /// text-only model, or when nothing is staged.
  List<Attachment> _usableAttachments(ModelInfo? model) {
    if (model == null || _pendingAttachments.isEmpty) return const [];
    return [
      for (final a in _pendingAttachments)
        if (_modelAccepts(model, a.kind)) a,
    ];
  }

  bool _modelAccepts(ModelInfo model, AttachmentKind kind) => switch (kind) {
        AttachmentKind.image => model.acceptsImages,
        AttachmentKind.audio => model.acceptsAudio,
      };

  /// Sidebar title for a chat opened with attachments and no text.
  String _attachmentSummary(List<Attachment> attachments) {
    final images = attachments.where((a) => a.kind == AttachmentKind.image).length;
    final audio = attachments.length - images;
    return [
      if (images > 0) '$images image${images == 1 ? '' : 's'}',
      if (audio > 0) '$audio recording${audio == 1 ? '' : 's'}',
    ].join(' + ');
  }

  /// Switches models, dropping anything staged that the new one can't accept.
  /// Silently carrying them to the send — where they'd be filtered out — would
  /// leave the user thinking an image went along when it never did.
  void _selectModel(ModelInfo? model) {
    final dropped = model == null
        ? _pendingAttachments.length
        : _pendingAttachments.where((a) => !_modelAccepts(model, a.kind)).length;
    setState(() {
      _selectedModel = model;
      if (model != null) {
        _pendingAttachments.removeWhere((a) => !_modelAccepts(model, a.kind));
      } else {
        _pendingAttachments.clear();
      }
    });
    if (dropped > 0) {
      _showAttachmentError(
          '${model?.name ?? 'This model'} doesn\'t accept those inputs — '
          '$dropped attachment${dropped == 1 ? '' : 's'} removed.');
    }
  }

  Future<void> _pickImages() async {
    try {
      final picked = await _attachments.pickImages();
      if (!mounted || picked.isEmpty) return;
      setState(() => _pendingAttachments.addAll(picked));
    } catch (e) {
      _showAttachmentError('Could not attach that image: $e');
    }
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      // Flip the flag first: stopRecording awaits the encoder flushing, and
      // the button must not look armed for another tap in the meantime.
      setState(() => _recording = false);
      try {
        final recorded = await _attachments.stopRecording();
        if (!mounted || recorded == null) return;
        setState(() => _pendingAttachments.add(recorded));
      } catch (e) {
        _showAttachmentError('Could not save that recording: $e');
      }
      return;
    }
    try {
      if (!await _attachments.hasMicPermission()) {
        _showAttachmentError('Microphone access was denied.');
        return;
      }
      await _attachments.startRecording();
      if (!mounted) {
        // The screen went away mid-start; don't leave the mic held open.
        await _attachments.cancelRecording();
        return;
      }
      setState(() => _recording = true);
    } catch (e) {
      _showAttachmentError('Could not start recording: $e');
    }
  }

  void _showAttachmentError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: const Color(0xFF3A1B1B)),
    );
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
          text: '(response stopped)',
          isUser: false,
          sender: _selectedModel == null ? null : _modelDisplayName(_selectedModel!)));
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

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Below this width the fixed 280px sidebar would swallow most of the
  /// screen — on a ~411dp phone it leaves the chat barely 130dp — so it moves
  /// into a drawer instead and the conversation gets the full width.
  static const double _sidebarBreakpoint = 720;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < _sidebarBreakpoint;
        final content = Column(
          children: [
            _buildTopBar(showMenuButton: narrow),
            if (_loadError != null) _buildWarningBanner(),
            Expanded(child: _buildBody()),
            if (!_loadingModels && !_checkingDownloads && _downloadedModels.isNotEmpty) _buildInputArea(),
          ],
        );
        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: mainColor,
          drawer: narrow
              ? Drawer(
                  backgroundColor: sidebarColor,
                  child: _buildSidebar(inDrawer: true),
                )
              : null,
          body: narrow
              // SafeArea only in the phone layout: it keeps the top bar clear
              // of the status bar and the input clear of the gesture pill.
              ? SafeArea(child: content)
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSidebar(),
                    Expanded(child: content),
                  ],
                ),
        );
      },
    );
  }

  // ---------------------------------------------------------------- sidebar

  /// [inDrawer] renders the same content for the phone layout's drawer, where
  /// it fills the drawer's own width and needs its own status-bar inset (the
  /// body's SafeArea doesn't cover the drawer overlay).
  Widget _buildSidebar({bool inDrawer = false}) {
    return Container(
      width: inDrawer ? null : 280,
      color: sidebarColor,
      child: SafeArea(
        bottom: false,
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
            Expanded(child: _buildSidebarTabContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarTabBar() {
    // Two rows of two: "Orchestration" doesn't fit alongside three other
    // labels in the 280px sidebar.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildSidebarTabButton('Models', _SidebarTab.models)),
              const SizedBox(width: 8),
              Expanded(child: _buildSidebarTabButton('Chat', _SidebarTab.chat)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: _buildSidebarTabButton('Orchestration', _SidebarTab.orchestration)),
              const SizedBox(width: 8),
              Expanded(child: _buildSidebarTabButton('Code', _SidebarTab.code)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarTabContent() {
    switch (_sidebarTab) {
      case _SidebarTab.models:
        return _buildModelsTab();
      case _SidebarTab.chat:
        return _buildChatTab();
      case _SidebarTab.orchestration:
        return _buildUnderConstructionTab(
          icon: Icons.account_tree_outlined,
          title: 'Orchestration',
          blurb: 'Routing a prompt across several models and combining their '
              'answers will live here.',
        );
      case _SidebarTab.code:
        return _buildUnderConstructionTab(
          icon: Icons.code,
          title: 'Code',
          blurb: 'Code-focused workspace — snippets, files and runnable '
              'output — will live here.',
        );
    }
  }

  Widget _buildUnderConstructionTab({
    required IconData icon,
    required String title,
    required String blurb,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: Colors.deepPurple.shade200),
            const SizedBox(height: 14),
            Text(title,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF3A2E14),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.construction, size: 14, color: Colors.amber),
                  SizedBox(width: 6),
                  Text('Under construction',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600, color: Colors.amber)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              blurb,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, height: 1.4, color: Colors.white38),
            ),
          ],
        ),
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
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ModelDetailScreen(
                model: m,
                runsInApp: inApp,
                source: inApp ? (m.id == onDeviceModelId ? onDeviceModelSource : m.gguf) : null,
                api: inApp ? null : _api,
              ),
            ));
            // The model's downloaded state may have changed (download/delete)
            // while its detail page was open — keep the chat picker in sync.
            if (mounted) _refreshDownloadedModels();
          },
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

  Widget _buildTopBar({bool showMenuButton = false}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: showMenuButton ? 8 : 24, vertical: 12),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: borderColor))),
      child: Row(
        children: [
          if (showMenuButton)
            IconButton(
              tooltip: 'Chats and models',
              icon: const Icon(Icons.menu, size: 22, color: Colors.white70),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),
          if (_loadingModels || _checkingDownloads)
            const Text('Loading models…', style: TextStyle(color: Colors.white54))
          else if (_downloadedModels.isNotEmpty)
            // Flexible so a long model name ellipsizes instead of overflowing
            // the row on a narrow screen.
            Flexible(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<ModelInfo>(
                  value: _selectedModel,
                  isExpanded: true,
                  dropdownColor: cardColor,
                  borderRadius: BorderRadius.circular(12),
                  icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white54),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                  items: _downloadedModels
                      .map((m) => DropdownMenuItem(
                            value: m,
                            child: Text(_modelDisplayName(m), overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: _sending ? null : _selectModel,
                ),
              ),
            )
          else
            const Text('No models downloaded', style: TextStyle(color: Colors.white54)),
          const Spacer(),
          IconButton(
            tooltip: 'Thinking indicator settings',
            icon: const Icon(Icons.tune, size: 20, color: Colors.white54),
            onPressed: _openThinkingSettings,
          ),
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
    if (_loadingModels || _checkingDownloads) {
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
    if (_downloadedModels.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.download_outlined, size: 40, color: Colors.white24),
              const SizedBox(height: 12),
              const Text('No models downloaded yet',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
              const SizedBox(height: 6),
              const Text('Visit the Models tab to download one before chatting.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white54)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => setState(() => _sidebarTab = _SidebarTab.models),
                child: const Text('Go to Models'),
              ),
            ],
          ),
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
    // Scrollable because on a phone the suggestions stack one-per-row and run
    // taller than the viewport — as a plain Column they overflowed instead.
    return SingleChildScrollView(
      child: Center(
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
                      children: _suggestionsFor(_session)
                          .map((s) => SizedBox(width: cardWidth, child: _buildSuggestionCard(s)))
                          .toList(),
                    );
                  },
                ),
              ],
            ),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.attachments.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    for (final a in message.attachments) _buildAttachmentChip(a),
                  ],
                ),
                // Only pad away from the text when there is text — an
                // image-only message shouldn't carry a trailing gap.
                if (message.text.isNotEmpty) const SizedBox(height: 8),
              ],
              if (message.text.isNotEmpty)
                SelectableText(message.text,
                    style: const TextStyle(color: Colors.white, height: 1.4)),
            ],
          ),
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
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: SizedBox(
                      width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ThinkingIndicator(
                      words: _thinkingSettings.activeWords,
                      // The thinking row only shows while _sending, and the
                      // user's message is appended right before that flips
                      // true (see _send), so it's always the last message.
                      query: _session.messages.isNotEmpty ? _session.messages.last.text : null,
                      modelName: _selectedModel?.name,
                    ),
                  ],
                ),
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
    final model = _selectedModel;
    final canAttachImages = model != null && model.acceptsImages;
    final canRecordAudio = model != null && model.acceptsAudio;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 14),
      child: Column(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_pendingAttachments.isNotEmpty) _buildPendingAttachments(),
                Container(
                  padding: EdgeInsets.only(left: canAttachImages ? 6 : 20, right: 8),
                  decoration: BoxDecoration(
                    color: cardColor,
                    border: Border.all(color: borderColor),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Row(
                    children: [
                      // Gated on the selected model: a text-only checkpoint has
                      // nowhere to put an image, so the button isn't offered
                      // rather than being shown and failing on send.
                      if (canAttachImages)
                        IconButton(
                          tooltip: 'Attach an image',
                          icon: const Icon(Icons.add, size: 22, color: Colors.white70),
                          onPressed: _sending || _recording ? null : _pickImages,
                        ),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          enabled: !_sending,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: _recording ? 'Recording…' : 'Send a message',
                            hintStyle: const TextStyle(color: Colors.white38),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                      if (canRecordAudio)
                        IconButton(
                          tooltip: _recording ? 'Stop recording' : 'Record audio',
                          icon: Icon(_recording ? Icons.stop_circle_outlined : Icons.mic_none,
                              size: 22,
                              color: _recording ? Colors.redAccent : Colors.white70),
                          onPressed: _sending ? null : _toggleRecording,
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
              ],
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

  /// Strip of thumbnails/chips above the text field for what's staged but not
  /// yet sent, each removable via its own ×.
  Widget _buildPendingAttachments() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < _pendingAttachments.length; i++)
            _buildAttachmentChip(
              _pendingAttachments[i],
              onRemove: () => setState(() => _pendingAttachments.removeAt(i)),
            ),
        ],
      ),
    );
  }

  Widget _buildAttachmentChip(Attachment attachment, {VoidCallback? onRemove}) {
    final isImage = attachment.kind == AttachmentKind.image;
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: EdgeInsets.fromLTRB(isImage ? 6 : 12, 6, onRemove == null ? 12 : 6, 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isImage)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                Uint8List.fromList(attachment.bytes),
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                // A file that picked cleanly can still fail to decode (wrong
                // extension, truncated); show the chip rather than a red box.
                errorBuilder: (_, _, _) => const SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(Icons.broken_image_outlined, size: 18, color: Colors.white38),
                ),
              ),
            )
          else
            const Icon(Icons.graphic_eq, size: 18, color: Colors.white70),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              attachment.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Remove',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(),
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.close, size: 16, color: Colors.white54),
              onPressed: onRemove,
            ),
          ],
        ],
      ),
    );
  }
}
