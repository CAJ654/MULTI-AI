import 'package:flutter/material.dart';
import 'package:llamadart/llamadart.dart' hide ChatSession;

import 'addons/addon_host.dart';
import 'addons/registry.dart';
import 'api_client.dart';
import 'app_shell.dart';
import 'attachment_input.dart';
import 'model_pool.dart';

/// The app's main screen. Since the add-on refactor this is a thin assembly
/// step — build the shared [ModelPool], register the add-ons, start the host —
/// and everything it used to draw now lives in `lib/addons/`.
///
/// Kept as the entry point (rather than having callers build an [AddOnHost]
/// themselves) because it is also where the test seams are: a widget test
/// hands in fakes here and gets the whole real app wired up behind them.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    ApiClient? apiClient,
    ModelDownloadManager? downloadManager,
    AttachmentSource? attachmentSource,
    this.onMarkdownLinkTap,
    this.addOnStateStore,
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

  // Injectable so widget tests can observe a Markdown link tap without the
  // url_launcher platform channel; production leaves this null and links open
  // in the platform browser.
  final void Function(String url)? onMarkdownLinkTap;

  /// Where the enabled/installed add-on state is kept. Tests pass an in-memory
  /// store so a run can't inherit — or leave behind — the developer's own
  /// choices in `%APPDATA%`.
  final AddOnStateStore? addOnStateStore;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ModelPool _pool = ModelPool(
    api: widget._apiClient,
    downloadManager: widget._downloadManager,
  );

  late final AddOnHost _host = AddOnHost(
    addOns: buildRegistry(
      attachmentSource: widget._attachmentSource,
      onMarkdownLinkTap: widget.onMarkdownLinkTap,
    ),
    modelPool: _pool,
    store: widget.addOnStateStore,
  );

  @override
  void initState() {
    super.initState();
    // Opens on the conversation, not on the first tab: Models sits leftmost
    // because that's the order you'd read them in, but chatting is what the
    // app is for.
    _host.start(initialTab: 'chat');
    _pool.refresh();
  }

  @override
  void dispose() {
    _host.dispose();
    _pool.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppShell(host: _host);
}
