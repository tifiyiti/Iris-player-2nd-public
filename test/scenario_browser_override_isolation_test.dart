import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';
import 'package:iris/features/scenario_playback/view/browse/paged_scenario_browse_data_source.dart';
import 'package:iris/features/scenario_playback/view/coordinator/scenario_browser_store.dart';
import 'package:iris/features/scenario_playback/view/sources/paged_scenario_sources_data_source.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/store/use_storage_store.dart';

/// Regression: a concurrently-mounted queue-override browser (the always-on
/// Windows dock — `playlistPanelMode = dockedRight`, `playlistPanelVisible =
/// true` by default) sets the GLOBAL
/// [ScenarioBrowserStore.queueOverrideMode]. The embedded storagedb scenario
/// manager must ignore that global slot and route with its OWN `queueOverride`
/// flag; otherwise Back/Home mutate the dock instead of navigating in place —
/// the "frozen storagedb, sidebar flips to the scenario sources" bug.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  setUpAll(() async {
    await DbModule.init(AppDatabase(NativeDatabase.memory()));
    usePlaybackScenarioStore();
    await usePlaybackScenarioStore().initialized;
    await runZonedGuarded(() async {
      usePlayQueueStore();
      await usePlayQueueStore().initialized;
      useAppStore();
      await useAppStore().initialized;
      useStorageStore();
      await useStorageStore().initialized;
    }, (Object e, StackTrace st) {});
  });

  setUp(() {
    final browser = useScenarioBrowserStore();
    browser
      ..resetQueueOverride()
      ..setMode(ScenarioBrowserMode.queue);
  });

  group('PagedScenarioSourcesDataSource override isolation', () {
    test('embedded manager back ignores the global dock override', () async {
      // Simulate the always-on dock: the global override slot is occupied.
      final browser = useScenarioBrowserStore()
        ..setQueueOverrideMode(ScenarioBrowserMode.queue);

      final ds = PagedScenarioSourcesDataSource(
        scenarioId: 'sc-isolation',
        embeddedInStoragesDb: true,
        queueOverride: false,
      );
      addTearDown(ds.dispose);
      await pumpEventQueue();

      final handled = await ds.handleNavigationBack();

      // Layer-1 root: not handled in place, falls through to the tabs.
      expect(handled, isFalse);
      // The dock's override slot must be untouched by the embedded manager.
      expect(browser.queueOverrideMode, ScenarioBrowserMode.queue);
    });

    test('queue-override manager back consumes in place', () async {
      final browser = useScenarioBrowserStore()
        ..setQueueOverrideMode(ScenarioBrowserMode.sources);

      final ds = PagedScenarioSourcesDataSource(
        scenarioId: 'sc-isolation',
        embeddedInStoragesDb: false,
        queueOverride: true,
      );
      addTearDown(ds.dispose);
      await pumpEventQueue();

      final handled = await ds.handleNavigationBack();

      expect(handled, isTrue);
      expect(browser.queueOverrideMode, ScenarioBrowserMode.queue);
    });
  });

  group('PagedScenarioBrowseDataSource override isolation', () {
    test('embedded manager back writes the persisted mode, not the override',
        () async {
      final browser = useScenarioBrowserStore()
        ..setMode(ScenarioBrowserMode.queue)
        ..setQueueOverrideMode(ScenarioBrowserMode.queue);

      final ds = PagedScenarioBrowseDataSource(
        scenarioId: 'sc-isolation',
        queueOverride: false,
      );
      addTearDown(ds.dispose);
      await pumpEventQueue();

      final handled = await ds.handleNavigationBack();

      expect(handled, isTrue);
      // Persisted manager mode advanced to Sources...
      expect(browser.state.mode, ScenarioBrowserMode.sources);
      // ...while the dock's override slot stayed on the queue.
      expect(browser.queueOverrideMode, ScenarioBrowserMode.queue);
    });

    test('queue-override manager back consumes in place', () async {
      final browser = useScenarioBrowserStore()
        ..setQueueOverrideMode(ScenarioBrowserMode.browse);

      final ds = PagedScenarioBrowseDataSource(
        scenarioId: 'sc-isolation',
        queueOverride: true,
      );
      addTearDown(ds.dispose);
      await pumpEventQueue();

      await ds.handleNavigationBack();

      expect(browser.queueOverrideMode, ScenarioBrowserMode.sources);
    });
  });
}
