import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:multi_ai/addons/addon.dart';
import 'package:multi_ai/addons/addon_host.dart';
import 'package:multi_ai/api_client.dart';
import 'package:multi_ai/app_shell.dart';
import 'package:multi_ai/model_pool.dart';

/// Counts its own lifecycle calls, so a test can assert what ran and how often
/// rather than inferring it from UI.
class _SpyAddOn extends AddOn {
  _SpyAddOn({
    this.id = 'spy',
    this.order = 0,
    this.schemaVersion = 1,
    this.requires = const [],
    this.essential = false,
    this.useCapability = false,
  });

  final String id;
  final int order;
  final int schemaVersion;
  final List<HostCapability> requires;
  final bool essential;

  /// Reaches for `model_pool` in registerUI. Paired with an empty [requires],
  /// this is the undeclared-use case the contract is supposed to catch.
  final bool useCapability;

  int installs = 0;
  int enables = 0;
  int disables = 0;

  @override
  AddOnManifest get manifest => AddOnManifest(
        id: id,
        title: id,
        icon: Icons.extension,
        order: order,
        requires: requires,
        schemaVersion: schemaVersion,
        essential: essential,
      );

  @override
  Future<void> onInstall(AddOnContext context) async => installs++;

  @override
  Future<void> onEnable(AddOnContext context) async => enables++;

  @override
  Future<void> onDisable() async => disables++;

  @override
  AddOnSurface registerUI(AddOnContext context) {
    if (useCapability) context.modelPool;
    return AddOnSurface(mainPane: (_) => Text('pane:$id'));
  }
}

class _EmptyApi extends ApiClient {
  @override
  Future<List<ModelInfo>> fetchModels() async => const [];
  @override
  Future<DeviceSpecs> fetchDeviceSpecs() async => const DeviceSpecs();
  @override
  Future<ServerModelCacheStatus> getServerModelCacheStatus(String modelId) async =>
      const ServerModelCacheStatus(cached: false);
}

void main() {
  group('lifecycle', () {
    test('install runs once, not again on the next launch', () async {
      final store = InMemoryAddOnStateStore();
      final first = _SpyAddOn();
      await AddOnHost(addOns: [first], store: store).start();
      expect(first.installs, 1);
      expect(first.enables, 1);

      // A second launch against the same stored state.
      final second = _SpyAddOn();
      await AddOnHost(addOns: [second], store: store).start();
      expect(second.installs, 0, reason: 'already installed at this schemaVersion');
      expect(second.enables, 1, reason: 'enable still runs every launch');
    });

    test('bumping schemaVersion re-runs install', () async {
      final store = InMemoryAddOnStateStore();
      await AddOnHost(addOns: [_SpyAddOn()], store: store).start();

      final upgraded = _SpyAddOn(schemaVersion: 2);
      await AddOnHost(addOns: [upgraded], store: store).start();
      expect(upgraded.installs, 1);
    });

    test('start is idempotent', () async {
      final spy = _SpyAddOn();
      final host = AddOnHost(addOns: [spy], store: InMemoryAddOnStateStore());
      await host.start();
      await host.start();
      expect(spy.enables, 1);
    });
  });

  group('enable and disable', () {
    test('a disabled add-on stays disabled across a restart', () async {
      final store = InMemoryAddOnStateStore();
      final spy = _SpyAddOn(id: 'extra');
      final host = AddOnHost(
        addOns: [_SpyAddOn(id: 'main', essential: true), spy],
        store: store,
      );
      await host.start();
      expect(host.entryFor('extra')!.enabled, isTrue);

      await host.setEnabled('extra', false);
      expect(spy.disables, 1);
      expect(host.entryFor('extra')!.enabled, isFalse);
      expect(host.entryFor('extra')!.surface, isNull,
          reason: 'a disabled add-on releases its UI');

      final restarted = _SpyAddOn(id: 'extra');
      final next = AddOnHost(
        addOns: [_SpyAddOn(id: 'main', essential: true), restarted],
        store: store,
      );
      await next.start();
      expect(next.entryFor('extra')!.enabled, isFalse);
      expect(restarted.enables, 0);
    });

    test('an essential add-on cannot be turned off', () async {
      final spy = _SpyAddOn(essential: true);
      final host = AddOnHost(addOns: [spy], store: InMemoryAddOnStateStore());
      await host.start();

      await host.setEnabled(spy.id, false);
      expect(host.entryFor(spy.id)!.enabled, isTrue);
      expect(spy.disables, 0);
    });

    test('disabling the active tab moves off it rather than stranding', () async {
      final host = AddOnHost(
        addOns: [_SpyAddOn(id: 'a', order: 0), _SpyAddOn(id: 'b', order: 1)],
        store: InMemoryAddOnStateStore(),
      );
      await host.start(initialTab: 'b');
      expect(host.active!.id, 'b');

      await host.setEnabled('b', false);
      expect(host.active!.id, 'a');
    });
  });

  group('capabilities', () {
    test('an add-on whose capability is missing is not enabled', () async {
      final spy = _SpyAddOn(requires: [HostCapability.modelPool]);
      // No modelPool given to the host at all.
      final host = AddOnHost(addOns: [spy], store: InMemoryAddOnStateStore());
      await host.start();

      final entry = host.entryFor(spy.id)!;
      expect(entry.available, isFalse);
      expect(entry.enabled, isFalse);
      expect(spy.enables, 0, reason: 'never enabled, so never half-initialized');
      expect(entry.missingCapabilities, [HostCapability.modelPool]);
      expect(entry.unavailableReason, contains('model_pool'));
    });

    test('using a capability without declaring it throws, naming the fix', () async {
      final spy = _SpyAddOn(useCapability: true); // requires: []
      final host = AddOnHost(
        addOns: [spy],
        modelPool: ModelPool(api: _EmptyApi()),
        store: InMemoryAddOnStateStore(),
      );

      await expectLater(
        host.start(),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            allOf(contains('model_pool'), contains('requires')))),
      );
    });

    test('a declared capability is handed over', () async {
      final pool = ModelPool(api: _EmptyApi());
      final spy = _SpyAddOn(requires: [HostCapability.modelPool], useCapability: true);
      final host = AddOnHost(
        addOns: [spy],
        modelPool: pool,
        store: InMemoryAddOnStateStore(),
      );
      await host.start();
      expect(host.entryFor(spy.id)!.enabled, isTrue);
    });
  });

  group('shell', () {
    testWidgets('an unavailable add-on shows a disabled tab with the reason, '
        'not a broken pane', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final host = AddOnHost(
        addOns: [
          _SpyAddOn(id: 'fine', order: 0),
          _SpyAddOn(id: 'needy', order: 1, requires: [HostCapability.modelPool]),
        ],
        store: InMemoryAddOnStateStore(),
      );
      await host.start();

      await tester.pumpWidget(MaterialApp(home: AppShell(host: host)));
      await tester.pumpAndSettle();

      // Both tabs are listed — silently dropping one reads as the feature
      // having been removed. ("fine" matches twice: the tab, plus the top-bar
      // title the shell falls back to for an add-on with no topBarSlot.)
      expect(find.text('fine'), findsWidgets);
      expect(find.text('needy'), findsOneWidget);
      // The usable one is showing; the unusable one explains itself.
      expect(find.text('pane:fine'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) =>
            w is Tooltip && (w.message ?? '').contains('model_pool')),
        findsOneWidget,
      );

      // Tapping the dead tab does nothing rather than throwing.
      await tester.tap(find.text('needy'));
      await tester.pumpAndSettle();
      expect(find.text('pane:fine'), findsOneWidget);
    });
  });
}
