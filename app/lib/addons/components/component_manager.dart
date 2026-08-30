import 'package:flutter/foundation.dart';

import '../../backend_process.dart' show ProvisionProgress;
import 'component.dart';
import 'component_runtime.dart';
import 'searxng_supervisor.dart';

/// The Add-ons tab's equivalent of `ModelPool`: what's installed, what's
/// running, and the one way to install/delete/run each component. Shared
/// (constructor-injected, the same way `attachmentSource` already is — see
/// `registry.dart`) between `ComponentsAddOn`, which lets the user manage
/// components, and `ChatAddOn`, which uses them.
class ComponentManager extends ChangeNotifier {
  ComponentManager() {
    refreshInstalled();
  }

  /// False on Android and under `flutter run` — nothing here has a bundled
  /// Python runtime to install into. Read by both the Add-ons tab (to show
  /// its unavailable pane) and Chat (to grey out the web-search toggle).
  bool get available => ComponentRuntime.available;

  final _installed = <String>{};

  /// IDs from [componentCatalog] currently installed on this machine.
  Set<String> get installedIds => Set.unmodifiable(_installed);

  bool isInstalled(String id) => _installed.contains(id);

  /// Re-reads install-marker state from disk. Cheap (marker-file existence
  /// checks only, see `ComponentRuntime.isInstalled`) so callers don't need
  /// to be precious about calling it.
  void refreshInstalled() {
    _installed
      ..clear()
      ..addAll([for (final c in componentCatalog) if (ComponentRuntime(c).isInstalled) c.id]);
    notifyListeners();
  }

  final _supervisors = <String, SearxngSupervisor>{};

  SearxngSupervisor _supervisorFor(LocalComponent component) =>
      _supervisors.putIfAbsent(component.id, () => SearxngSupervisor(ComponentRuntime(component)));

  /// Whether [id]'s process is currently running. Always false for a
  /// [ComponentKind.tool] component — it has no persistent process to be
  /// running or not; every use is a fresh one-shot call (see
  /// `ComponentRuntime.runModule`).
  bool isRunning(String id) {
    final component = componentById(id);
    if (component == null || component.kind != ComponentKind.server) return false;
    return _supervisorFor(component).isRunning;
  }

  /// Starts [id]'s process if it isn't already running. A no-op for a
  /// [ComponentKind.tool] component. Lazy by design — called right before the
  /// first use in a session (see `WebSearchClient`), not at app launch, so
  /// installing a component never itself starts a process the user hasn't
  /// actually asked to use yet.
  Future<void> ensureRunning(String id) async {
    final component = componentById(id);
    if (component == null || component.kind != ComponentKind.server) return;
    await _supervisorFor(component).start();
  }

  /// Installs [component], streaming pip's output. Refreshes [installedIds]
  /// when the stream ends, whether it succeeded or failed — a failed install
  /// may still have left a completed-but-unmarked site-packages directory
  /// behind, and re-checking costs nothing.
  Stream<ProvisionProgress> install(LocalComponent component) async* {
    final runtime = ComponentRuntime(component);
    try {
      await for (final progress in runtime.provision()) {
        yield progress;
      }
    } finally {
      refreshInstalled();
    }
  }

  /// Stops [component] if running, then deletes everything it installed.
  Future<void> uninstall(LocalComponent component) async {
    if (component.kind == ComponentKind.server) {
      await _supervisorFor(component).stop();
    }
    await ComponentRuntime(component).delete();
    refreshInstalled();
  }

  /// Stops every running component's process. Called when the Add-ons tab is
  /// disabled and on app shutdown (see `ComponentsAddOn.onDisable` and
  /// `chat_screen.dart`'s dispose).
  Future<void> stopAll() async {
    for (final supervisor in _supervisors.values) {
      await supervisor.stop();
    }
  }
}
