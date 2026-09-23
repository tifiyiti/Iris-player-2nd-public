import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/scenario_playback/view/browse/paged_scenario_browse_data_source.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/store/use_storage_store.dart';

/// F-008: the scenario browse page disables multi-select — its selection
/// action list is empty, so long-press must never enter a dead selection mode.
void main() {
  setUpAll(() async {
    final db = AppDatabase(NativeDatabase.memory());
    DbModule.init(db);
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

  test('browse disables selection (F-008)', () async {
    // Seeded construction avoids the unseeded `_loadStorages` path (which has
    // an unrelated pre-existing `late final _crumbTail` double-assignment).
    final ds = PagedScenarioBrowseDataSource(
      scenarioId: 'x',
      initialStorageId: 's',
      initialPath: '',
    );
    await pumpEventQueue();
    expect(ds.supportsSelection, isFalse);
    ds.dispose();
  });
}
