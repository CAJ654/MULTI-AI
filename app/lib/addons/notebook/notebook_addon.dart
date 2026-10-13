import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../../api_client.dart' show ModelInfo;
import '../../model_pool.dart';
import '../../theme.dart';
import '../addon.dart';
import '../chat/chat_controller.dart' show modelDisplayName;
import 'memory_store.dart';
import 'notebook_main_pane.dart';
import 'notebook_sidebar_panel.dart';
import 'source_ingestion.dart';

/// Ingest sources, then ask questions grounded in them — the TODO's planned
/// Agentic OS memory browser, in its first increment. See
/// `memory_store.dart`'s doc comment for why, unlike `CodeAddOn`/
/// `ComponentsAddOn`, this declares no unavailable-pane branch: nothing it
/// needs is platform-specific.
class NotebookAddOn extends AddOn {
  NotebookController? _controller;

  @override
  AddOnManifest get manifest => const AddOnManifest(
        id: 'notebook',
        title: 'Notebook',
        icon: Icons.menu_book_outlined,
        order: 5,
        requires: [HostCapability.modelPool, HostCapability.memory],
      );

  @override
  Future<void> onEnable(AddOnContext context) async {
    _controller = NotebookController(memory: context.memory, modelPool: context.modelPool);
  }

  @override
  Future<void> onDisable() async {
    _controller?.dispose();
    _controller = null;
  }

  @override
  AddOnSurface registerUI(AddOnContext context) {
    final controller = _controller!;
    return AddOnSurface(
      sidebarPanel: (_) => NotebookSidebarPanel(controller: controller),
      mainPane: (_) => NotebookMainPane(controller: controller),
      topBarSlot: (_) => NotebookModelPicker(controller: controller),
    );
  }
}

/// Drives the notebook tab: which notebook is selected, its sources/notes,
/// and the one "ask" action that retrieves then generates. Built once per
/// enable by [NotebookAddOn.registerUI] and shared by the sidebar and main
/// pane, the same way `ModelPool`/`ComponentManager` are shared across the
/// widgets that read them — but scoped to this tab, not host-level, since
/// "which notebook is selected" is this add-on's own state, not something
/// any other tab needs.
class NotebookController extends ChangeNotifier {
  NotebookController({required this.memory, required this.modelPool}) {
    _ingestion = SourceIngestion(memory);
    unawaited(refreshNotebooks());
    // Mirrors ChatController.start()'s own pool subscription (chat_controller.dart):
    // track which models are downloaded so the picker can't be left pointing
    // at one that no longer is, and read what's already there immediately —
    // enabling an add-on is asynchronous, so the roster can easily have
    // finished loading before this subscribes.
    modelPool.addListener(_onModelPoolChanged);
    _onModelPoolChanged();
  }

  final MemoryStore memory;
  final ModelPool modelPool;
  late final SourceIngestion _ingestion;

  List<Notebook> notebooks = const [];
  int? selectedNotebookId;
  List<RawItem> sources = const [];

  /// Every chat thread in the selected notebook — see `memory_store.dart`'s
  /// `Chat` doc comment for why a notebook holds several rather than one
  /// running transcript.
  List<Chat> chats = const [];
  int? selectedChatId;
  List<Output> outputs = const [];

  /// The model `ask()` sends to — picked from `modelPool.downloaded`, same
  /// roster Chat's own picker draws from. Null only when nothing is
  /// downloaded yet, in which case `ask()` falls back to the built-in
  /// on-device model rather than leaving the user stuck.
  ModelInfo? selectedModel;

  /// True while an ingest/ask is in flight — the main pane disables its
  /// inputs on this rather than letting a second request race the first.
  bool busy = false;

  /// One sentence for the main pane, e.g. a failed fetch or generation.
  /// Cleared at the start of the next action.
  String? error;

  Future<void> refreshNotebooks() async {
    notebooks = await memory.listNotebooks();
    if (selectedNotebookId == null && notebooks.isNotEmpty) {
      selectedNotebookId = notebooks.first.id;
    }
    await _refreshSelected();
    notifyListeners();
  }

  Future<void> _refreshSelected() async {
    final id = selectedNotebookId;
    if (id == null) {
      sources = const [];
      chats = const [];
      selectedChatId = null;
      outputs = const [];
      return;
    }
    sources = await memory.listSources(id);
    chats = await memory.listChats(id);
    // Keep the current chat selected if it still exists in this notebook;
    // otherwise fall back to the most recently created one.
    if (selectedChatId == null || chats.every((c) => c.id != selectedChatId)) {
      selectedChatId = chats.isEmpty ? null : chats.last.id;
    }
    await _refreshOutputs();
  }

  Future<void> _refreshOutputs() async {
    final chatId = selectedChatId;
    outputs = chatId == null ? const [] : await memory.listOutputs(chatId);
  }

  Future<void> selectNotebook(int id) async {
    if (selectedNotebookId == id) return;
    selectedNotebookId = id;
    await _refreshSelected();
    notifyListeners();
  }

  Future<void> createNotebook(String title) async {
    final notebook = await memory.createNotebook(title);
    notebooks = await memory.listNotebooks();
    selectedNotebookId = notebook.id;
    await _refreshSelected();
    notifyListeners();
  }

  Future<void> deleteNotebook(int id) async {
    await memory.deleteNotebook(id);
    if (selectedNotebookId == id) selectedNotebookId = null;
    await refreshNotebooks();
  }

  Future<void> selectChat(int id) async {
    if (selectedChatId == id) return;
    selectedChatId = id;
    await _refreshOutputs();
    notifyListeners();
  }

  Future<void> createChat([String? title]) async {
    final notebookId = selectedNotebookId;
    if (notebookId == null) return;
    final chat = await memory.createChat(notebookId, title ?? 'Chat ${chats.length + 1}');
    chats = await memory.listChats(notebookId);
    selectedChatId = chat.id;
    await _refreshOutputs();
    notifyListeners();
  }

  Future<void> deleteChat(int id) async {
    await memory.deleteChat(id);
    if (selectedChatId == id) selectedChatId = null;
    await _refreshSelected();
    notifyListeners();
  }

  /// Re-picks the model if the current one just stopped being downloadable —
  /// identical gating/logic to ChatController's own `_onPoolChanged`.
  void _onModelPoolChanged() {
    if (modelPool.ready) {
      final downloaded = modelPool.downloaded;
      if (selectedModel == null || !modelPool.downloadedIds.contains(selectedModel!.id)) {
        selectedModel = downloaded.isNotEmpty ? downloaded.first : null;
      }
    }
    notifyListeners();
  }

  void selectModel(ModelInfo? model) {
    selectedModel = model;
    notifyListeners();
  }

  Future<void> addPastedText(String title, String text) async {
    final id = selectedNotebookId;
    if (id == null || text.trim().isEmpty) return;
    await _ingestion.addPastedText(id, title: title.trim().isEmpty ? 'Pasted text' : title, text: text);
    await _refreshSelected();
    notifyListeners();
  }

  /// A bad/unreachable URL surfaces via [error], not a thrown exception —
  /// an expected outcome for user-supplied input, not a bug.
  Future<void> addUrl(Uri url) async {
    final id = selectedNotebookId;
    if (id == null) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final item = await _ingestion.addUrl(id, url);
      if (item == null) {
        error = "Couldn't fetch that page.";
        return;
      }
      await _refreshSelected();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> addTextFile() async {
    final id = selectedNotebookId;
    if (id == null) return;
    busy = true;
    notifyListeners();
    try {
      final item = await _ingestion.addTextFile(id);
      if (item != null) await _refreshSelected();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Retrieves the most relevant chunks for [question] from the selected
  /// notebook, then asks a chat model to answer grounded in them, saving
  /// both the question and the reply as notes in the selected chat —
  /// creating a first one lazily if the notebook has none yet, so asking a
  /// question needs no separate "new chat" step the first time.
  Future<void> ask(String question) async {
    final notebookId = selectedNotebookId;
    if (notebookId == null || question.trim().isEmpty) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      var chatId = selectedChatId;
      if (chatId == null) {
        final chat = await memory.createChat(notebookId, 'Chat 1');
        chats = await memory.listChats(notebookId);
        selectedChatId = chatId = chat.id;
      }
      final chunks = await memory.search(notebookId, question);
      final groundedContext = chunks.isEmpty
          ? 'No sources in this notebook yet.'
          : chunks.map((c) => 'From "${c.sourceTitle}":\n${c.text}').join('\n\n---\n\n');
      final prompt = 'Answer the question using only the sources below. If they '
          "don't cover it, say so plainly.\n\nSources:\n$groundedContext\n\n"
          'Question: $question';
      final model = selectedModel ?? ModelPool.builtInOnDevice;
      await memory.addOutput(chatId, author: 'user', text: question);
      final reply = await modelPool.generate(model: model, prompt: prompt);
      await memory.addOutput(chatId, author: 'ai', text: reply);
      await _refreshOutputs();
    } catch (e) {
      error = 'Could not get an answer: $e';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    modelPool.removeListener(_onModelPoolChanged);
    super.dispose();
  }
}

// --------------------------------------------------------------- top bar

/// Which model `ask()` sends to — the notebook tab's top-bar slot, mirroring
/// `chat_addon.dart`'s `ChatModelPicker` (same dropdown-over-the-downloaded-
/// roster shape) but with no thinking-indicator button, since that's a
/// chat-specific setting this tab has no equivalent of.
class NotebookModelPicker extends StatelessWidget {
  const NotebookModelPicker({super.key, required this.controller});

  final NotebookController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final pool = controller.modelPool;
        final downloaded = pool.downloaded;
        if (pool.loading || pool.checkingDownloads) {
          return const Text('Loading models…', style: TextStyle(color: Colors.white54));
        }
        if (downloaded.isEmpty) {
          return const Text('No models downloaded', style: TextStyle(color: Colors.white54));
        }
        // Flexible so a long model name ellipsizes instead of overflowing the
        // row on a narrow screen — same reasoning as ChatModelPicker's.
        return Flexible(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<ModelInfo>(
              value: controller.selectedModel,
              isExpanded: true,
              dropdownColor: cardColor,
              borderRadius: BorderRadius.circular(12),
              icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white54),
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
              items: downloaded
                  .map((m) =>
                      DropdownMenuItem(value: m, child: Text(modelDisplayName(m), overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: controller.busy ? null : controller.selectModel,
            ),
          ),
        );
      },
    );
  }
}
