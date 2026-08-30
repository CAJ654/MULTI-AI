import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../api_client.dart';
import '../../attachment_input.dart';
import '../../chat_store.dart';
import '../../copy_button.dart';
import '../../markdown_text.dart';
import '../../theme.dart';
import '../../thinking_indicator.dart';
import '../../thinking_settings_dialog.dart';
import '../addon.dart';
import '../components/component_manager.dart';
import 'chat_controller.dart';
import 'web_access_explainer_dialog.dart';
import 'web_source.dart';

/// The conversation tab: a list of chats in the sidebar, the transcript and
/// composer in the main pane, and the model picker in the top bar.
///
/// Essential — every other add-on can be switched off, but an app with no tabs
/// at all has nothing to show.
class ChatAddOn extends AddOn {
  ChatAddOn({
    required this.componentManager,
    this.attachmentSource,
    this.onMarkdownLinkTap,
    this.modelsAddOnId = 'models',
    this.componentsAddOnId = 'components',
  });

  /// Injectable so widget tests can drive the attach/mic buttons without
  /// opening a real file dialog or recording from a real microphone.
  final AttachmentSource? attachmentSource;

  /// Injectable so widget tests can observe a Markdown link tap without the
  /// url_launcher platform channel; production leaves this null and links open
  /// in the platform browser.
  final void Function(String url)? onMarkdownLinkTap;

  /// Which tab the "Go to Models" button jumps to. Named rather than hardcoded
  /// so the button quietly does nothing if that add-on isn't registered,
  /// instead of the two files having to know about each other.
  final String modelsAddOnId;

  /// Which tab the web-search toggle's "install it" prompt jumps to — see
  /// [modelsAddOnId] for why this is named rather than hardcoded.
  final String componentsAddOnId;

  /// Shared with the Add-ons tab — see `component_manager.dart`'s doc
  /// comment for why this is a plain injected object rather than a
  /// `HostCapability`.
  final ComponentManager componentManager;

  ChatController? _controller;

  @override
  AddOnManifest get manifest => const AddOnManifest(
        id: 'chat',
        title: 'Chat',
        icon: Icons.chat_bubble_outline,
        order: 1,
        requires: [HostCapability.modelPool],
        essential: true,
      );

  @override
  Future<void> onEnable(AddOnContext context) async {
    final controller = ChatController(
      pool: context.modelPool,
      componentManager: componentManager,
      attachmentSource: attachmentSource,
    );
    _controller = controller;
    // Not awaited: history and settings load from disk, and blocking the whole
    // app's startup on that would leave a spinner up for a filesystem round
    // trip. The widgets rebuild when it lands.
    unawaited(controller.start());
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
      sidebarPanel: (_) => ChatSessionList(controller: controller),
      mainPane: (_) => ChatPane(
        controller: controller,
        onMarkdownLinkTap: onMarkdownLinkTap,
        onGoToModels: () => context.showTab(modelsAddOnId),
        onGoToAddOns: () => context.showTab(componentsAddOnId),
      ),
      topBarSlot: (_) => ChatModelPicker(controller: controller),
    );
  }
}

// ------------------------------------------------------------------ sidebar

/// New Chat, plus every conversation that has something in it.
class ChatSessionList extends StatelessWidget {
  const ChatSessionList({super.key, required this.controller});

  final ChatController controller;

  Future<void> _showSessionMenu(
      BuildContext context, Offset position, int index) async {
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
    if (action == 'delete') controller.deleteSession(index);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        // A chat only appears here once it has a message; a freshly opened
        // (still empty) chat stays hidden.
        final sessions = controller.sessions;
        final visible = [
          for (var i = 0; i < sessions.length; i++)
            if (sessions[i].messages.isNotEmpty) i,
        ];
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
                onPressed: controller.newSession,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New Chat'),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: visible.length,
                itemBuilder: (context, i) {
                  final index = visible[i];
                  final s = sessions[index];
                  final selected = index == controller.activeSessionIndex;
                  return GestureDetector(
                    // Right-click (or long-press on touch) opens the chat's
                    // context menu with Delete.
                    onSecondaryTapUp: (details) =>
                        _showSessionMenu(context, details.globalPosition, index),
                    child: Material(
                      color: selected ? cardColor : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      child: ListTile(
                        dense: true,
                        shape:
                            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        leading: const Icon(Icons.chat_bubble_outline,
                            size: 16, color: Colors.white54),
                        title: Text(
                          s.title ?? 'New chat',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              color: selected ? Colors.white : Colors.white70),
                        ),
                        onTap: () => controller.selectSession(index),
                        onLongPress: () {
                          final box = context.findRenderObject() as RenderBox?;
                          final origin = box?.localToGlobal(Offset.zero) ?? Offset.zero;
                          _showSessionMenu(context, origin, index);
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ------------------------------------------------------------------ top bar

/// Model picker plus the thinking-indicator settings button. Chat-specific:
/// both only mean something while a conversation is on screen.
class ChatModelPicker extends StatelessWidget {
  const ChatModelPicker({super.key, required this.controller});

  final ChatController controller;

  void _openThinkingSettings(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => ThinkingSettingsDialog(
        initial: controller.thinkingSettings,
        onChanged: controller.updateThinkingSettings,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final pool = controller.pool;
        final downloaded = pool.downloaded;
        return Row(
          children: [
            if (pool.loading || pool.checkingDownloads)
              const Text('Loading models…', style: TextStyle(color: Colors.white54))
            else if (downloaded.isNotEmpty)
              // Flexible so a long model name ellipsizes instead of overflowing
              // the row on a narrow screen.
              Flexible(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<ModelInfo>(
                    value: controller.selectedModel,
                    isExpanded: true,
                    dropdownColor: cardColor,
                    borderRadius: BorderRadius.circular(12),
                    icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white54),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                    items: downloaded
                        .map((m) => DropdownMenuItem(
                              value: m,
                              child:
                                  Text(modelDisplayName(m), overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: controller.sending ? null : controller.selectModel,
                  ),
                ),
              )
            else
              const Text('No models downloaded', style: TextStyle(color: Colors.white54)),
            const Spacer(),
            IconButton(
              tooltip: 'Thinking indicator settings',
              icon: const Icon(Icons.tune, size: 20, color: Colors.white54),
              onPressed: () => _openThinkingSettings(context),
            ),
          ],
        );
      },
    );
  }
}

// --------------------------------------------------------------- main pane

/// Transcript and composer. Owns the scroll position and the send button;
/// everything else it reads off [ChatController].
class ChatPane extends StatefulWidget {
  const ChatPane({
    super.key,
    required this.controller,
    this.onMarkdownLinkTap,
    this.onGoToModels,
    this.onGoToAddOns,
  });

  final ChatController controller;
  final void Function(String url)? onMarkdownLinkTap;
  final VoidCallback? onGoToModels;

  /// Where the web-search toggle's "install it" tooltip sends the user when
  /// SearXNG isn't installed yet.
  final VoidCallback? onGoToAddOns;

  @override
  State<ChatPane> createState() => _ChatPaneState();
}

class _ChatPaneState extends State<ChatPane> {
  final _scrollController = ScrollController();
  bool _showScrollToBottom = false;
  StreamSubscription<String>? _errorSub;
  int _lastScrollRevision = 0;

  ChatController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _lastScrollRevision = _c.scrollRevision;
    _c.addListener(_onControllerChanged);
    _errorSub = _c.errors.listen(_showError);
  }

  @override
  void dispose() {
    _errorSub?.cancel();
    _c.removeListener(_onControllerChanged);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// The controller can't reach the ScrollController — it outlives this widget
  /// — so it bumps a counter instead and we scroll when it moves.
  void _onControllerChanged() {
    if (_c.scrollRevision != _lastScrollRevision) {
      _lastScrollRevision = _c.scrollRevision;
      _scrollToBottom();
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: const Color(0xFF3A1B1B)),
    );
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
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final pool = _c.pool;
        final ready = !pool.loading && !pool.checkingDownloads;
        return Column(
          children: [
            Expanded(child: _buildBody()),
            if (ready && pool.downloaded.isNotEmpty) _buildInputArea(),
          ],
        );
      },
    );
  }

  Widget _buildBody() {
    final pool = _c.pool;
    if (pool.loading || pool.checkingDownloads) {
      return const Center(child: CircularProgressIndicator());
    }
    if (pool.models.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('No models available: ${pool.loadError}',
                style: TextStyle(color: Colors.red.shade300)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: pool.refresh, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (pool.downloaded.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.download_outlined, size: 40, color: Colors.white24),
              const SizedBox(height: 12),
              const Text('No models downloaded yet',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
              const SizedBox(height: 6),
              const Text('Visit the Models tab to download one before chatting.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white54)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: widget.onGoToModels,
                child: const Text('Go to Models'),
              ),
            ],
          ),
        ),
      );
    }
    final session = _c.session;
    if (session.messages.isEmpty) {
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
              itemCount: session.messages.length + (_c.sending ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == session.messages.length) return _buildThinkingRow();
                return _buildMessageRow(session.messages[index]);
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
                  style: TextStyle(
                      fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white),
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
                      children: _c
                          .suggestionsFor(_c.session)
                          .map((s) =>
                              SizedBox(width: cardWidth, child: _buildSuggestionCard(s)))
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

  Widget _buildSuggestionCard(Suggestion s) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _c.sending ? null : () => _c.send(s.prompt),
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
                // Error rows are diagnostic strings, not model Markdown — render
                // them plain (and red) so a stray * or _ in an exception message
                // isn't reinterpreted as formatting. Every model reply goes
                // through the Markdown renderer.
                if (message.isError)
                  SelectableText(
                    message.text,
                    style: TextStyle(height: 1.5, color: Colors.red.shade300),
                  )
                else
                  MarkdownText(
                    message.text,
                    baseStyle: const TextStyle(height: 1.5, color: Colors.white),
                    onTapLink: widget.onMarkdownLinkTap,
                  ),
                if (message.text.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: CopyButton(message.text),
                  ),
                ],
                if (message.sources.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildSourceStrip(message.sources),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Numbered citation chips under a grounded reply — the "show sources, not
  /// just a trust-me answer" half of the web-access plan's ethics table. Each
  /// opens its URL; reuses `markdown_text.dart`'s promoted [openExternalUrl]
  /// rather than duplicating the same four lines a second time.
  Widget _buildSourceStrip(List<WebSource> sources) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var i = 0; i < sources.length; i++)
          _SourceChip(index: i + 1, source: sources[i], onTap: openExternalUrl),
      ],
    );
  }

  Widget _buildThinkingRow() {
    final session = _c.session;
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
                      words: _c.thinkingSettings.activeWords,
                      // The thinking row only shows while sending, and the
                      // user's message is appended right before that flips
                      // true (see ChatController.send), so it's always last.
                      query: session.messages.isNotEmpty ? session.messages.last.text : null,
                      modelName: _c.selectedModel?.name,
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
    final model = _c.selectedModel;
    final canAttachImages = model != null && model.acceptsImages;
    final canRecordAudio = model != null && model.acceptsAudio;
    final sending = _c.sending;
    final recording = _c.recording;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 14),
      child: Column(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_c.pendingAttachments.isNotEmpty) _buildPendingAttachments(),
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
                          onPressed: sending || recording ? null : _c.pickImages,
                        ),
                      _buildWebAccessToggle(),
                      Expanded(
                        child: TextField(
                          controller: _c.textController,
                          enabled: !sending,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: recording ? 'Recording…' : 'Send a message',
                            hintStyle: const TextStyle(color: Colors.white38),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (_) => _c.send(),
                        ),
                      ),
                      if (canRecordAudio)
                        IconButton(
                          tooltip: recording ? 'Stop recording' : 'Record audio',
                          icon: Icon(recording ? Icons.stop_circle_outlined : Icons.mic_none,
                              size: 22, color: recording ? Colors.redAccent : Colors.white70),
                          onPressed: sending ? null : _c.toggleRecording,
                        ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: IconButton.filled(
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.deepPurple.shade400,
                            disabledBackgroundColor: Colors.white10,
                          ),
                          tooltip: sending ? 'Stop response' : 'Send',
                          icon: Icon(sending ? Icons.stop_rounded : Icons.arrow_upward,
                              size: 20, color: Colors.white),
                          onPressed: sending ? _c.stopResponse : _c.send,
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
    final pending = _c.pendingAttachments;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < pending.length; i++)
            _buildAttachmentChip(
              pending[i],
              onRemove: () => _c.removeAttachment(i),
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

  // ------------------------------------------------------------- web access

  /// The composer's "search the web for this reply" chip — three states:
  /// off, on, and disabled-with-tooltip when SearXNG isn't installed. Stays
  /// visible-but-greyed rather than disappearing when unavailable, the same
  /// "never silently drop, always show why" convention `app_shell.dart`
  /// already applies to whole tabs.
  Widget _buildWebAccessToggle() {
    final available = _c.webAccessAvailable;
    final enabled = _c.webAccessEnabled;
    if (!available) {
      return IconButton(
        tooltip: 'Install web search from the Add-ons tab',
        icon: const Icon(Icons.public_off, size: 20, color: Colors.white24),
        onPressed: widget.onGoToAddOns,
      );
    }
    return IconButton(
      tooltip: enabled ? 'Web search is on for this message' : 'Search the web for this reply',
      icon: Icon(Icons.public,
          size: 20, color: enabled ? Colors.deepPurple.shade200 : Colors.white70),
      onPressed: _c.sending ? null : _onToggleWebAccess,
    );
  }

  Future<void> _onToggleWebAccess() async {
    if (_c.webAccessEnabled) {
      _c.setWebAccessEnabled(false);
      return;
    }
    if (!_c.webAccessExplainerSeen) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => const WebAccessExplainerDialog(),
      );
      _c.markWebAccessExplainerSeen();
      if (confirmed != true) return;
    }
    _c.setWebAccessEnabled(true);
  }
}

/// One numbered citation chip — see `_ChatPaneState._buildSourceStrip`.
class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.index, required this.source, required this.onTap});

  final int index;
  final WebSource source;
  final void Function(String url) onTap;

  @override
  Widget build(BuildContext context) {
    final host = Uri.tryParse(source.url)?.host ?? source.url;
    return Material(
      color: cardColor,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onTap(source.url),
        child: Tooltip(
          message: source.title,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$index. ',
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600, color: Colors.deepPurple.shade200)),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(
                    host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
