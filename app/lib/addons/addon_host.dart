import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../chat_store.dart' show appDataFile;
import '../model_pool.dart';
import 'addon.dart';

/// One add-on as the host sees it: the add-on itself, whether it can run, and
/// its UI once built.
class AddOnEntry {
  AddOnEntry._(this.addOn, {required this.missingCapabilities});

  final AddOn addOn;

  /// Declared capabilities the host can't supply. Non-empty means this add-on
  /// cannot be enabled, and its tab shows why rather than a broken pane.
  final List<HostCapability> missingCapabilities;

  AddOnManifest get manifest => addOn.manifest;
  String get id => manifest.id;

  bool get available => missingCapabilities.isEmpty;

  bool _enabled = false;
  bool get enabled => _enabled;

  AddOnSurface? _surface;

  /// Built on enable and kept — an add-on's widgets are rebuilt on every tab
  /// switch, but its surface (and whatever state the builders close over) is
  /// not. That is what lets a reply arrive while the user is on another tab.
  AddOnSurface? get surface => _surface;

  /// One sentence for the disabled tab, e.g. "Needs model_pool, which this
  /// build doesn't provide."
  String get unavailableReason {
    final names = missingCapabilities.map((c) => c.wireName).join(', ');
    return 'Needs $names, which this build doesn\'t provide.';
  }
}

/// Owns the registered add-ons: runs their lifecycle, remembers which are
/// switched on, and hands out capability-checked contexts.
///
/// State machine per add-on: **registered → installed → enabled**. Registration
/// is compile-time (see registry.dart). Install is once per
/// [AddOnManifest.schemaVersion] and means first-run setup, not fetching code.
/// Enable is the part the user controls, and it persists.
class AddOnHost extends ChangeNotifier {
  AddOnHost({
    required List<AddOn> addOns,
    this.modelPool,
    AddOnStateStore? store,
  })  : _store = store ?? AddOnStateStore(),
        _entries = [
          for (final addOn in addOns)
            AddOnEntry._(
              addOn,
              missingCapabilities:
                  AddOnContext.missingFor(addOn.manifest, modelPool: modelPool),
            ),
        ]..sort((a, b) => a.manifest.order.compareTo(b.manifest.order));

  final ModelPool? modelPool;
  final AddOnStateStore _store;
  final List<AddOnEntry> _entries;

  List<AddOnEntry> get entries => List.unmodifiable(_entries);

  /// The add-ons with a tab, in tab order. Unavailable ones are included —
  /// they render disabled, because silently dropping a tab reads as a bug.
  List<AddOnEntry> get tabs => entries;

  String? _activeId;

  /// The add-on currently on screen. Null before [start] completes.
  AddOnEntry? get active {
    final id = _activeId;
    if (id == null) return null;
    return _entries.where((e) => e.id == id).firstOrNull;
  }

  bool _started = false;
  bool get started => _started;

  AddOnEntry? entryFor(String id) => _entries.where((e) => e.id == id).firstOrNull;

  AddOnContext _contextFor(AddOnEntry entry) => AddOnContext(
        manifest: entry.manifest,
        modelPool: modelPool,
        showTab: showTab,
      );

  /// Runs install-then-enable for every available add-on, restoring the user's
  /// on/off choices. Safe to call once.
  Future<void> start({String? initialTab}) async {
    if (_started) return;
    final state = await _store.load();
    for (final entry in _entries) {
      if (!entry.available) continue;
      final context = _contextFor(entry);
      if (state.installedVersion(entry.id) != entry.manifest.schemaVersion) {
        await entry.addOn.onInstall(context);
        state.setInstalledVersion(entry.id, entry.manifest.schemaVersion);
      }
      // Absent from the file means never toggled: on by default. An essential
      // add-on ignores a stored `false` — it may have been written by a build
      // where it wasn't essential yet.
      final wanted = entry.manifest.essential || (state.isEnabled(entry.id) ?? true);
      if (wanted) await _enableEntry(entry, context);
    }
    await _store.save(state);
    _activeId = _resolveInitialTab(initialTab);
    _started = true;
    notifyListeners();
  }

  String? _resolveInitialTab(String? preferred) {
    final candidates = _entries.where((e) => e.enabled);
    if (preferred != null && candidates.any((e) => e.id == preferred)) {
      return preferred;
    }
    return candidates.firstOrNull?.id;
  }

  Future<void> _enableEntry(AddOnEntry entry, AddOnContext context) async {
    if (entry._enabled) return;
    await entry.addOn.onEnable(context);
    entry._surface = entry.addOn.registerUI(context);
    entry._enabled = true;
  }

  void showTab(String id) {
    final entry = entryFor(id);
    if (entry == null || !entry.enabled || _activeId == id) return;
    _activeId = id;
    notifyListeners();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final entry = entryFor(id);
    if (entry == null || !entry.available) return;
    if (entry.manifest.essential && !enabled) return;
    if (entry.enabled == enabled) return;

    if (enabled) {
      await _enableEntry(entry, _contextFor(entry));
    } else {
      await entry.addOn.onDisable();
      entry._surface = null;
      entry._enabled = false;
      // Don't strand the user on a tab that just went away.
      if (_activeId == id) _activeId = _resolveInitialTab(null);
    }

    final state = await _store.load();
    state.setEnabled(id, enabled);
    await _store.save(state);
    notifyListeners();
  }

  @override
  void dispose() {
    for (final entry in _entries) {
      if (entry.enabled) entry.addOn.onDisable();
    }
    super.dispose();
  }
}

/// Which add-ons are switched on, and which schemaVersion each was last
/// installed at. A small JSON file next to the chat history.
class AddOnState {
  AddOnState._(this._enabled, this._installed);

  AddOnState.empty() : this._({}, {});

  final Map<String, bool> _enabled;
  final Map<String, int> _installed;

  /// Null means the user has never expressed a preference for this add-on.
  bool? isEnabled(String id) => _enabled[id];
  void setEnabled(String id, bool value) => _enabled[id] = value;

  int? installedVersion(String id) => _installed[id];
  void setInstalledVersion(String id, int version) => _installed[id] = version;

  Map<String, dynamic> toJson() => {'enabled': _enabled, 'installed': _installed};

  /// Tolerant by design: an entry this build doesn't understand is skipped
  /// rather than failing the load, so downgrading doesn't wipe the file.
  factory AddOnState.fromJson(Map<String, dynamic> json) {
    final enabled = <String, bool>{};
    for (final e in (json['enabled'] as Map<String, dynamic>? ?? {}).entries) {
      if (e.value is bool) enabled[e.key] = e.value as bool;
    }
    final installed = <String, int>{};
    for (final e in (json['installed'] as Map<String, dynamic>? ?? {}).entries) {
      if (e.value is int) installed[e.key] = e.value as int;
    }
    return AddOnState._(enabled, installed);
  }
}

class AddOnStateStore {
  Future<AddOnState> load() async {
    try {
      final file = await appDataFile('addons.json');
      if (!await file.exists()) return AddOnState.empty();
      return AddOnState.fromJson(
          jsonDecode(await file.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      // A corrupt or unreadable file means defaults, not a dead app.
      return AddOnState.empty();
    }
  }

  Future<void> save(AddOnState state) async {
    try {
      final file = await appDataFile('addons.json');
      await file.writeAsString(jsonEncode(state.toJson()));
    } catch (_) {
      // Best-effort, exactly like ChatStore: the choice still holds in memory
      // for this session.
    }
  }
}

/// In-memory store for tests and for any platform where the real one can't
/// write. Behaves like a file that starts empty.
class InMemoryAddOnStateStore implements AddOnStateStore {
  AddOnState _state = AddOnState.empty();

  @override
  Future<AddOnState> load() async =>
      AddOnState.fromJson(jsonDecode(jsonEncode(_state.toJson())) as Map<String, dynamic>);

  @override
  Future<void> save(AddOnState state) async => _state = state;
}
