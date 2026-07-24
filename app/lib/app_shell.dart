import 'dart:async';

import 'package:flutter/material.dart';

import 'addons/addon_host.dart';
import 'backend_process.dart';
import 'storage_settings_dialog.dart';
import 'theme.dart';
import 'update_service.dart';

/// The frame every add-on draws inside: sidebar with the tab bar, top bar,
/// banners, and the active add-on's main pane.
///
/// Owns nothing about models or conversations — those belong to the add-ons.
/// What's left here is genuinely app-wide: the layout, which tab is showing,
/// and the two banners (backend unreachable, update ready) that apply no
/// matter what is on screen.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.host});

  final AddOnHost host;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Mirrors UpdateService's latest status so the banner can react to it. Seeded
  // from the service rather than from `idle`, because the check starts in
  // StartupGate and may well have finished before this screen was built.
  UpdateStatus _updateStatus = UpdateService.instance.status;
  StreamSubscription<UpdateStatus>? _updateSub;

  AddOnHost get _host => widget.host;

  /// Below this width the fixed 280px sidebar would swallow most of the
  /// screen — on a ~411dp phone it leaves the chat barely 130dp — so it moves
  /// into a drawer instead and the conversation gets the full width.
  static const double _sidebarBreakpoint = 720;

  @override
  void initState() {
    super.initState();
    _updateSub = UpdateService.instance.onChange.listen((status) {
      if (mounted) setState(() => _updateStatus = status);
    });
  }

  @override
  void dispose() {
    _updateSub?.cancel();
    super.dispose();
  }

  void _showTab(String id) {
    _host.showTab(id);
    // On a phone the tabs live in the drawer, so picking one has to close it.
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
  }

  void _openStorageSettings() {
    showDialog<void>(
      context: context,
      builder: (_) => const StorageSettingsDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pool = _host.modelPool;
    return ListenableBuilder(
      // The pool as well as the host: the backend-unreachable banner is read
      // straight off the pool, so the shell has to repaint when it changes.
      listenable: pool == null ? _host : Listenable.merge([_host, pool]),
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < _sidebarBreakpoint;
            final active = _host.active;
            final content = Column(
              children: [
                _buildTopBar(active, showMenuButton: narrow),
                if (_backendError != null) _buildWarningBanner(_backendError!),
                if (_updateStatus.state == UpdateState.ready) _buildUpdateBanner(),
                // The chrome renders on the first frame and the pane catches
                // up: enabling the add-ons is asynchronous, and holding the
                // whole window back for it would flash an empty screen over
                // what is usually a single microtask.
                Expanded(
                  child: active?.surface?.mainPane(context) ??
                      const Center(child: CircularProgressIndicator()),
                ),
              ],
            );
            return Scaffold(
              key: _scaffoldKey,
              backgroundColor: mainColor,
              drawer: narrow
                  ? Drawer(
                      backgroundColor: sidebarColor,
                      child: _buildSidebar(active, inDrawer: true),
                    )
                  : null,
              body: narrow
                  // SafeArea only in the phone layout: it keeps the top bar clear
                  // of the status bar and the input clear of the gesture pill.
                  ? SafeArea(child: content)
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildSidebar(active),
                        Expanded(child: content),
                      ],
                    ),
            );
          },
        );
      },
    );
  }

  /// The backend-unreachable warning. Read off the pool rather than tracked
  /// here — the shell has no state of its own to go stale.
  String? get _backendError => _host.modelPool?.loadError;

  // ---------------------------------------------------------------- sidebar

  /// [inDrawer] renders the same content for the phone layout's drawer, where
  /// it fills the drawer's own width and needs its own status-bar inset (the
  /// body's SafeArea doesn't cover the drawer overlay).
  Widget _buildSidebar(AddOnEntry? active, {bool inDrawer = false}) {
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
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                ],
              ),
            ),
            _buildTabBar(active),
            const SizedBox(height: 8),
            Expanded(
              child: active?.surface?.sidebarPanel?.call(context) ??
                  const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  /// Two per row: "Orchestration" doesn't fit alongside three other labels in
  /// the 280px sidebar. Laid out from the registry, so a fifth add-on wraps to
  /// a third row on its own.
  Widget _buildTabBar(AddOnEntry? active) {
    final tabs = _host.tabs;
    final rows = <Widget>[];
    for (var i = 0; i < tabs.length; i += 2) {
      final pair = tabs.skip(i).take(2).toList();
      rows.add(Row(
        children: [
          for (var j = 0; j < pair.length; j++) ...[
            if (j > 0) const SizedBox(width: 8),
            Expanded(child: _buildTabButton(pair[j], active)),
          ],
          // Keeps a lone trailing tab the same width as the ones above it
          // rather than stretching across the sidebar.
          if (pair.length == 1) ...[
            const SizedBox(width: 8),
            const Expanded(child: SizedBox.shrink()),
          ],
        ],
      ));
      if (i + 2 < tabs.length) rows.add(const SizedBox(height: 8));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(children: rows),
    );
  }

  Widget _buildTabButton(AddOnEntry entry, AddOnEntry? active) {
    final selected = entry.id == active?.id;
    // An add-on whose capabilities this build can't supply stays visible but
    // inert, with the reason in its tooltip. Dropping the tab silently would
    // read as the feature having been removed.
    final usable = entry.available && entry.enabled;
    final button = Material(
      color: selected ? cardColor : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: usable ? () => _showTab(entry.id) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            entry.manifest.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: !usable
                  ? Colors.white24
                  : selected
                      ? Colors.white
                      : Colors.white54,
            ),
          ),
        ),
      ),
    );
    if (usable) return button;
    return Tooltip(
      message: entry.available
          ? '${entry.manifest.title} is turned off.'
          : entry.unavailableReason,
      child: button,
    );
  }

  // ---------------------------------------------------------------- top bar

  Widget _buildTopBar(AddOnEntry? active, {bool showMenuButton = false}) {
    final slot = active?.surface?.topBarSlot;
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
          // The add-on fills the bar; anything it doesn't use pushes the
          // shell's own buttons to the right, as an empty Spacer would.
          Expanded(
            child: slot == null
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Text(active?.manifest.title ?? '',
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
                  )
                : slot(context),
          ),
          // Only in a packaged build. Everything it controls is about the
          // downloaded runtime and what uninstalling does to it, neither of
          // which exists under `flutter run`.
          if (BackendRuntime.isBundled)
            IconButton(
              tooltip: 'Storage',
              icon: const Icon(Icons.sd_storage_outlined, size: 20, color: Colors.white54),
              onPressed: _openStorageSettings,
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- banners

  Widget _buildWarningBanner(String message) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF3A2E14),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(
              child:
                  Text(message, style: const TextStyle(fontSize: 13, color: Colors.amber))),
          TextButton(
            onPressed: () => _host.modelPool?.refresh(),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  /// Shown only once a new version is fully downloaded and applying it is
  /// instant. Nothing appears while checking or downloading: an update the
  /// user cannot act on yet is just noise, and this sits above a conversation
  /// they are in the middle of.
  Widget _buildUpdateBanner() {
    final version = _updateStatus.version;
    return Container(
      width: double.infinity,
      color: const Color(0xFF1B2A3A),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.download_done_rounded, size: 16, color: Color(0xFF7DB3E8)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              version == null
                  ? 'An update is ready to install.'
                  : 'Multi-AI $version is ready to install.',
              style: const TextStyle(fontSize: 13, color: Color(0xFF7DB3E8)),
            ),
          ),
          FilledButton(
            // Does not return on success: Velopack swaps the app files and
            // starts the new version as a fresh process. If it fails there is
            // nothing more useful to do than leave the banner up to retry.
            onPressed: () => UpdateService.instance.applyAndRestart().ignore(),
            child: const Text('Relaunch to Update'),
          ),
        ],
      ),
    );
  }
}
