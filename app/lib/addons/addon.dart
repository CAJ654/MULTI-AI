import 'package:flutter/material.dart';

import '../model_pool.dart';

/// A service the host owns and lends to add-ons. An add-on lists the ones it
/// needs in [AddOnManifest.requires]; reaching for one it didn't declare
/// throws, so the declaration is enforced rather than documentation.
///
/// Deliberately a short list. The next one to land is likely `memory`, once
/// the SQLite-vs-PocketBase question in the README is settled — adding it is a
/// new enum case plus a getter on [AddOnContext], not a redesign.
enum HostCapability {
  modelPool('model_pool');

  const HostCapability(this.wireName);

  /// Stable name for logs and for the add-on's own error messages.
  final String wireName;
}

/// What an add-on declares about itself. Everything the host needs to decide
/// whether it can run, where its tab goes, and when to initialize it.
@immutable
class AddOnManifest {
  const AddOnManifest({
    required this.id,
    required this.title,
    required this.icon,
    required this.order,
    this.requires = const [],
    this.schemaVersion = 1,
    this.essential = false,
  });

  /// Stable identifier. This is the persistence key for enabled/installed
  /// state, so renaming one resets that add-on for existing users.
  final String id;

  /// Sidebar tab label.
  final String title;

  final IconData icon;

  /// Tab position, ascending. Not the list order in the registry, so an
  /// add-on can be slotted in without editing its neighbours.
  final int order;

  final List<HostCapability> requires;

  /// Bump to re-run [AddOn.onInstall] after a release changes what that
  /// first-run setup has to produce. Same idea as a migration number.
  final int schemaVersion;

  /// Essential add-ons can't be turned off. Chat is one: an app whose every
  /// tab has been disabled has nothing to show.
  final bool essential;
}

/// The three places an add-on can draw. All are built lazily by the host, and
/// only for the active add-on.
@immutable
class AddOnSurface {
  const AddOnSurface({required this.mainPane, this.sidebarPanel, this.topBarSlot});

  /// The main area, right of the sidebar. Owns everything below the top bar,
  /// including a bottom input bar if the add-on wants one.
  final WidgetBuilder mainPane;

  /// Contents of the sidebar below the tab bar. Null renders nothing there.
  final WidgetBuilder? sidebarPanel;

  /// Contents of the top bar, left of the shared settings icons — chat puts
  /// its model picker here. Null leaves the space empty.
  final WidgetBuilder? topBarSlot;
}

/// A unit of the app that owns a tab: chat, the model browser, orchestration.
///
/// Add-ons are registered at compile time and have a lifecycle at runtime —
/// Flutter ships as machine code with no interpreter, so there is no way to
/// load one after install, and [onInstall] means "first-run setup on this
/// machine", not "fetch and install code". New add-ons reach users through an
/// app update. See the plan notes in the README's Core section.
abstract class AddOn {
  const AddOn();

  AddOnManifest get manifest;

  /// One-time setup for this add-on on this machine — seed defaults, create
  /// its storage. Runs once, and again only when [AddOnManifest.schemaVersion]
  /// changes. Never on a normal launch.
  Future<void> onInstall(AddOnContext context) async {}

  /// Every launch while enabled, and again when the user re-enables it. Where
  /// long-lived state gets built.
  Future<void> onEnable(AddOnContext context) async {}

  /// Turned off by the user, or the app is going away. Release anything held.
  Future<void> onDisable() async {}

  /// The add-on's UI. Called once per enable, not per frame — an add-on that
  /// needs to repaint should hold a [ChangeNotifier] and have its widgets
  /// listen, as chat does.
  AddOnSurface registerUI(AddOnContext context);
}

/// Everything an add-on is handed. Capabilities are checked on access rather
/// than injected wholesale, so an undeclared use fails loudly at the point of
/// the mistake instead of silently working.
class AddOnContext {
  AddOnContext({
    required AddOnManifest manifest,
    ModelPool? modelPool,
    void Function(String addOnId)? showTab,
  })  : _manifest = manifest,
        _modelPool = modelPool,
        _showTab = showTab;

  final AddOnManifest _manifest;
  final ModelPool? _modelPool;
  final void Function(String addOnId)? _showTab;

  /// The shared model roster and the one way to run a model.
  ModelPool get modelPool => _capability(HostCapability.modelPool, _modelPool);

  /// Switches to another add-on's tab — chat's "Go to Models" button. Not a
  /// capability: navigating between tabs needs no permission, and an add-on
  /// naming one that isn't there is a no-op rather than an error.
  void showTab(String addOnId) => _showTab?.call(addOnId);

  T _capability<T>(HostCapability capability, T? value) {
    if (!_manifest.requires.contains(capability)) {
      throw StateError(
        "Add-on '${_manifest.id}' used the ${capability.wireName} capability "
        'without declaring it. Add HostCapability.${capability.name} to its '
        "manifest's requires list.",
      );
    }
    if (value == null) {
      throw StateError(
        "The ${capability.wireName} capability is unavailable, so '${_manifest.id}' "
        'should not have been enabled.',
      );
    }
    return value;
  }

  /// Which of [requires] the host cannot supply. Empty means the add-on can
  /// be enabled.
  static List<HostCapability> missingFor(
    AddOnManifest manifest, {
    ModelPool? modelPool,
  }) {
    return [
      for (final capability in manifest.requires)
        if (switch (capability) {
          HostCapability.modelPool => modelPool == null,
        })
          capability,
    ];
  }
}
