import 'dart:async';

import 'package:flutter/material.dart';

import '../../api_client.dart';
import '../../attachment_input.dart';
import '../../chat_store.dart';
import '../../model_pool.dart';
import '../../on_device_engine.dart';
import '../../thinking_settings.dart';

/// Stands in for a reply the user cut short. Shown in the transcript but kept
/// out of the history sent to the model — it's UI state, not something said.
const String stoppedPlaceholder = '(response stopped)';

/// Chat UI model names always end in an explicit "(on-device)" / "(local
/// server)" tag so it's clear which one is answering — the raw name from
/// the backend isn't consistent about this (on-device sibling files bake in
/// "(On-Device)", but the built-in Qwen2.5 0.5B and gguf-only entries like
/// GPT-OSS don't have any suffix at all).
String modelDisplayName(ModelInfo m) {
  final inApp = m.id == onDeviceModelId || m.gguf != null;
  const rawSuffix = ' (On-Device)';
  var base = m.name;
  if (base.endsWith(rawSuffix)) {
    base = base.substring(0, base.length - rawSuffix.length);
  }
  return inApp ? '$base (on-device)' : '$base (local server)';
}

/// Everything the chat tab knows: its conversations, what's staged to send,
/// which model answers, and whether a reply is in flight.
///
/// Split out of the widgets so the three surfaces chat contributes — the
/// session list in the sidebar, the transcript in the main pane, and the model
/// picker in the top bar — read one source of truth, and so the state outlives
/// a tab switch. A reply that arrives while the user is looking at the Models
/// tab still lands in its conversation.
class ChatController extends ChangeNotifier {
  ChatController({
    required this.pool,
    AttachmentSource? attachmentSource,
    ChatStore? store,
    ThinkingSettingsStore? thinkingSettingsStore,
  })  : _providedAttachments = attachmentSource,
        _store = store ?? ChatStore(),
        _thinkingSettingsStore = thinkingSettingsStore ?? ThinkingSettingsStore();

  final ModelPool pool;
  final AttachmentSource? _providedAttachments;
  final ChatStore _store;
  final ThinkingSettingsStore _thinkingSettingsStore;

  /// Built on first use, never at construction: [DefaultAttachmentSource]
  /// opens a `record` platform channel in its constructor, which throws
  /// outright under `flutter test`. A chat that never touches the attach or
  /// mic button must not pay for one.
  late final AttachmentSource _attachments =
      _providedAttachments ?? DefaultAttachmentSource();

  /// Whether the recorder/picker was ever built — so [dispose] doesn't
  /// construct one purely in order to tear it down.
  bool _attachmentsUsed = false;

  AttachmentSource get _attachmentSource {
    _attachmentsUsed = true;
    return _attachments;
  }

  /// The message being composed. Held here rather than in the pane so its text
  /// survives a tab switch, and so [send] can clear it at exactly the point
  /// the message is accepted.
  final textController = TextEditingController();

  final _sessions = <ChatSession>[ChatSession()];
  int _activeSession = 0;

  List<ChatSession> get sessions => List.unmodifiable(_sessions);
  int get activeSessionIndex => _activeSession;
  ChatSession get session => _sessions[_activeSession];

  ModelInfo? _selectedModel;

  /// Which model the next send goes to. Chat-local: another add-on selecting
  /// models must not move this picker.
  ModelInfo? get selectedModel => _selectedModel;

  bool _sending = false;
  bool get sending => _sending;

  bool _recording = false;
  bool get recording => _recording;

  final _pendingAttachments = <Attachment>[];
  List<Attachment> get pendingAttachments => List.unmodifiable(_pendingAttachments);

  ThinkingSettings _thinkingSettings = ThinkingSettings.defaults();
  ThinkingSettings get thinkingSettings => _thinkingSettings;

  /// Bumped every time the transcript should be scrolled to the bottom. The
  /// pane owns the ScrollController, so it watches this instead of being
  /// called directly.
  int _scrollRevision = 0;
  int get scrollRevision => _scrollRevision;

  final _errors = StreamController<String>.broadcast();

  /// Problems worth a snackbar rather than a message row — a failed image
  /// pick, a denied microphone.
  Stream<String> get errors => _errors.stream;

  // Bumped on every send and on stop; a reply whose generation no longer
  // matches was stopped by the user and gets discarded on arrival.
  int _sendGeneration = 0;
  ChatSession? _pendingSession;

  // Suggestions are randomized once per session and cached here, so they stay
  // put across rebuilds (typing, dialogs closing, etc.) but reshuffle whenever
  // a genuinely new chat is started.
  final _sessionSuggestions = <ChatSession, List<Suggestion>>{};

  List<Suggestion> suggestionsFor(ChatSession session) =>
      _sessionSuggestions.putIfAbsent(session, pickRandomSuggestions);

  /// Loads persisted history and settings, and starts tracking the pool so the
  /// picker can't be left pointing at a model that is no longer downloaded.
  Future<void> start() async {
    pool.addListener(_onPoolChanged);
    // And read what's already there. Enabling an add-on is asynchronous, so
    // the roster can easily have finished loading before this subscribes —
    // a listener that only reacts to the *next* change would then leave the
    // picker empty until something unrelated moved.
    _onPoolChanged();
    await Future.wait([_loadStoredSessions(), _loadThinkingSettings()]);
  }

  Future<void> _loadStoredSessions() async {
    final stored = await _store.load();
    if (stored.isEmpty) return;
    // Keep the fresh empty session on top and resume with history below it.
    _sessions.addAll(stored);
    notifyListeners();
  }

  Future<void> _loadThinkingSettings() async {
    _thinkingSettings = await _thinkingSettingsStore.load();
    notifyListeners();
  }

  void updateThinkingSettings(ThinkingSettings settings) {
    _thinkingSettings = settings;
    _thinkingSettingsStore.save(settings);
    notifyListeners();
  }

  /// Re-picks the model if the current one just stopped being downloadable.
  ///
  /// Gated on [ModelPool.ready]: mid-refresh the roster and the download set
  /// are briefly inconsistent, and reconciling against that would drop a
  /// perfectly valid selection for a frame.
  void _onPoolChanged() {
    if (pool.ready) {
      final downloaded = pool.downloaded;
      if (_selectedModel == null || !pool.downloadedIds.contains(_selectedModel!.id)) {
        _selectedModel = downloaded.isNotEmpty ? downloaded.first : null;
      }
    }
    notifyListeners();
  }

  // ------------------------------------------------------------- sessions

  void newSession() {
    // Reuse an existing empty session (they're hidden from the sidebar, so
    // stacking up duplicates would leak invisible entries).
    final existing = _sessions.indexWhere((s) => s.messages.isEmpty);
    if (existing >= 0) {
      _activeSession = existing;
    } else {
      _sessions.insert(0, ChatSession());
      _activeSession = 0;
    }
    notifyListeners();
  }

  void selectSession(int index) {
    _activeSession = index;
    notifyListeners();
  }

  void deleteSession(int index) {
    _sessionSuggestions.remove(_sessions[index]);
    _sessions.removeAt(index);
    if (_sessions.isEmpty) _sessions.add(ChatSession());
    if (_activeSession >= _sessions.length) {
      _activeSession = _sessions.length - 1;
    } else if (index < _activeSession) {
      _activeSession -= 1;
    }
    notifyListeners();
    _store.save(_sessions);
  }

  // ----------------------------------------------------------------- send

  Future<void> send([String? preset]) async {
    final text = (preset ?? textController.text).trim();
    final model = _selectedModel;
    // Attachments are only staged while a model that accepts them is picked,
    // but the picker can change between staging and sending — drop anything
    // the current model can't take rather than having the backend reject it.
    final attachments = usableAttachments(model);
    if (model == null || _sending) return;
    // An attachment alone is a valid message ("what's in this picture?" is
    // implied); text alone still isn't when there's nothing attached.
    if (text.isEmpty && attachments.isEmpty) return;

    final session = this.session;
    // Snapshot before the new message is appended, so history is strictly the
    // turns that came before it. Error rows and the "(response stopped)"
    // placeholder are excluded — they're UI state, not things the model said.
    final history = [
      for (final m in session.messages)
        if (!m.isError && m.text != stoppedPlaceholder)
          ChatTurn(isUser: m.isUser, text: m.text),
    ];
    final generation = ++_sendGeneration;
    _pendingSession = session;
    session.title ??= text.isEmpty ? _attachmentSummary(attachments) : text;
    session.messages
        .add(ChatMessage(text: text, isUser: true, attachments: attachments));
    _pendingAttachments.clear();
    _sending = true;
    textController.clear();
    _scrollRevision++;
    notifyListeners();
    _store.save(_sessions);

    try {
      // Which of the two run paths this model takes is the pool's call — see
      // ModelPool.generate.
      final reply = await pool.generate(
        model: model,
        prompt: text,
        attachments: attachments,
        history: history,
      );
      if (generation != _sendGeneration) return; // stopped by the user
      session.messages
          .add(ChatMessage(text: reply, isUser: false, sender: modelDisplayName(model)));
      notifyListeners();
    } catch (e) {
      if (generation != _sendGeneration) return; // aborting throws; not a real error
      session.messages.add(ChatMessage(
          text: e.toString(),
          isUser: false,
          sender: modelDisplayName(model),
          isError: true));
      notifyListeners();
    } finally {
      if (generation == _sendGeneration) {
        _pendingSession = null;
        _sending = false;
        _scrollRevision++;
        notifyListeners();
      }
      _store.save(_sessions);
    }
  }

  void stopResponse() {
    if (!_sending) return;
    _sendGeneration++; // orphan the in-flight request so its reply is discarded
    pool.cancel();
    final session = _pendingSession;
    _pendingSession = null;
    _sending = false;
    session?.messages.add(ChatMessage(
        text: stoppedPlaceholder,
        isUser: false,
        sender: _selectedModel == null ? null : modelDisplayName(_selectedModel!)));
    notifyListeners();
    _store.save(_sessions);
  }

  // ---------------------------------------------------------- attachments

  /// The staged attachments [model] can actually accept. Empty for a
  /// text-only model, or when nothing is staged.
  List<Attachment> usableAttachments(ModelInfo? model) {
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
  void selectModel(ModelInfo? model) {
    final dropped = model == null
        ? _pendingAttachments.length
        : _pendingAttachments.where((a) => !_modelAccepts(model, a.kind)).length;
    _selectedModel = model;
    if (model != null) {
      _pendingAttachments.removeWhere((a) => !_modelAccepts(model, a.kind));
    } else {
      _pendingAttachments.clear();
    }
    notifyListeners();
    if (dropped > 0) {
      _errors.add('${model?.name ?? 'This model'} doesn\'t accept those inputs — '
          '$dropped attachment${dropped == 1 ? '' : 's'} removed.');
    }
  }

  void removeAttachment(int index) {
    _pendingAttachments.removeAt(index);
    notifyListeners();
  }

  Future<void> pickImages() async {
    try {
      final picked = await _attachmentSource.pickImages();
      if (picked.isEmpty) return;
      _pendingAttachments.addAll(picked);
      notifyListeners();
    } catch (e) {
      _errors.add('Could not attach that image: $e');
    }
  }

  Future<void> toggleRecording() async {
    if (_recording) {
      // Flip the flag first: stopRecording awaits the encoder flushing, and
      // the button must not look armed for another tap in the meantime.
      _recording = false;
      notifyListeners();
      try {
        final recorded = await _attachmentSource.stopRecording();
        if (recorded == null) return;
        _pendingAttachments.add(recorded);
        notifyListeners();
      } catch (e) {
        _errors.add('Could not save that recording: $e');
      }
      return;
    }
    try {
      if (!await _attachmentSource.hasMicPermission()) {
        _errors.add('Microphone access was denied.');
        return;
      }
      await _attachmentSource.startRecording();
      _recording = true;
      notifyListeners();
    } catch (e) {
      _errors.add('Could not start recording: $e');
    }
  }

  @override
  void dispose() {
    pool.removeListener(_onPoolChanged);
    textController.dispose();
    if (_attachmentsUsed) _attachments.dispose();
    _errors.close();
    super.dispose();
  }
}

class Suggestion {
  const Suggestion(this.title, this.subtitle);

  final String title;
  final String subtitle;

  String get prompt => '$title $subtitle';
}

// Shared pool the empty-state screen draws 4 suggestions from at random. Kept
// larger than any one screenful so repeat visits to "New Chat" don't always
// show the same four.
const suggestionPool = [
  Suggestion('Tell me a fun fact', 'about the Roman Empire'),
  Suggestion('Show me a code snippet', "of a website's sticky header"),
  Suggestion('Help me study', 'vocabulary for a college entrance exam'),
  Suggestion('Give me ideas', "for what to do with my kids' art"),
  Suggestion('Write a short story', 'about a lighthouse keeper'),
  Suggestion('Explain a concept', 'like quantum entanglement, simply'),
  Suggestion('Plan a trip', 'to Japan for two weeks'),
  Suggestion('Debug my code', 'for a Python off-by-one error'),
  Suggestion('Draft an email', 'declining a meeting politely'),
  Suggestion('Suggest a recipe', "using what's in my fridge"),
  Suggestion('Brainstorm names', 'for a new coffee shop'),
  Suggestion('Summarize an article', 'on climate policy'),
  Suggestion('Create a workout plan', 'for a beginner runner'),
  Suggestion('Explain the math', 'behind compound interest'),
  Suggestion('Give me a book recommendation', 'similar to Dune'),
  Suggestion('Help me practice', 'for a job interview'),
];

const _suggestionCount = 4;

List<Suggestion> pickRandomSuggestions() {
  final pool = List<Suggestion>.from(suggestionPool)..shuffle();
  return pool.take(_suggestionCount).toList();
}
