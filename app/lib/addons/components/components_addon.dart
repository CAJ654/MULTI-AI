import 'package:flutter/material.dart';

import '../../theme.dart';
import '../addon.dart';
import 'component.dart';
import 'component_detail_screen.dart';
import 'component_manager.dart';

/// Where components like the bundled SearXNG instance are downloaded and
/// deleted — the Add-ons tab equivalent of the Models tab, but for local
/// services a *feature* needs (Chat's web-search toggle) rather than for the
/// model weights chat itself runs on. See `component_manager.dart` for why
/// this is a plain shared object rather than a `HostCapability`: Chat is
/// essential and must keep working with nothing here installed at all.
class ComponentsAddOn extends AddOn {
  ComponentsAddOn({required this.manager});

  final ComponentManager manager;

  @override
  AddOnManifest get manifest => const AddOnManifest(
        id: 'components',
        title: 'Add-ons',
        icon: Icons.extension_outlined,
        order: 4,
      );

  @override
  Future<void> onDisable() async => manager.stopAll();

  @override
  AddOnSurface registerUI(AddOnContext context) {
    if (!manager.available) {
      return AddOnSurface(mainPane: (_) => _unavailablePane());
    }
    return AddOnSurface(
      sidebarPanel: (_) => ComponentRosterList(manager: manager),
      mainPane: (_) => const ComponentsPane(),
    );
  }

  /// Same shape as `CodeAddOn`'s Android pane: components install into the
  /// packaged Windows build's bundled Python runtime, which doesn't exist
  /// under `flutter run` or on Android — a hard "not available" rather than a
  /// smaller version of the tab.
  Widget _unavailablePane() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.extension_off_outlined, size: 52, color: Colors.deepPurple.shade200),
              const SizedBox(height: 16),
              const Text('Add-ons',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white)),
              const SizedBox(height: 10),
              const Text(
                'Not available here. Add-ons install into the packaged Windows '
                "build's bundled Python runtime, which this build doesn't have.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, height: 1.5, color: Colors.white38),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ sidebar

/// One card per catalog entry — mirrors `ModelRosterList`/`ModelCard` in
/// `addons/models/models_addon.dart`.
class ComponentRosterList extends StatelessWidget {
  const ComponentRosterList({super.key, required this.manager});

  final ComponentManager manager;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) => ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        itemCount: componentCatalog.length,
        itemBuilder: (context, i) =>
            ComponentCard(component: componentCatalog[i], manager: manager),
      ),
    );
  }
}

/// The main pane while the Add-ons tab is active — a pointer to the sidebar
/// list, not a second copy of it. Mirrors `ModelsPane`.
class ComponentsPane extends StatelessWidget {
  const ComponentsPane({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.extension_outlined, size: 52, color: Colors.deepPurple.shade200),
              const SizedBox(height: 16),
              const Text('Add-ons',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white)),
              const SizedBox(height: 10),
              const Text(
                'Optional local services other tabs can use — like the web search '
                "Chat's search toggle needs. Pick one from the list to install or "
                'remove it.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, height: 1.4, color: Colors.white38),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ComponentCard extends StatelessWidget {
  const ComponentCard({super.key, required this.component, required this.manager});

  final LocalComponent component;
  final ComponentManager manager;

  @override
  Widget build(BuildContext context) {
    final installed = manager.isInstalled(component.id);
    final running = manager.isRunning(component.id);
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
            builder: (_) => ComponentDetailScreen(component: component, manager: manager),
          )),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  component.kind == ComponentKind.server ? Icons.dns_outlined : Icons.terminal,
                  size: 18,
                  color: Colors.deepPurple.shade200,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(component.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                      const SizedBox(height: 4),
                      Text('~${component.approxInstalledMb} MB',
                          style: const TextStyle(fontSize: 12, color: Colors.white54)),
                      const SizedBox(height: 2),
                      Text(
                        !installed
                            ? 'Not installed'
                            : component.kind == ComponentKind.server
                                ? (running ? 'Installed · running' : 'Installed')
                                : 'Installed',
                        style: TextStyle(
                          fontSize: 11,
                          color: installed ? Colors.greenAccent.shade200 : Colors.white38,
                        ),
                      ),
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
}
