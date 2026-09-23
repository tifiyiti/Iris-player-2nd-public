import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/meta_settings/meta_settings_module.dart';
import 'package:iris/features/virtual_media/model/enum/vm_enums.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_app_store.dart';

import 'helpers/sqlite3_loader.dart';

/// Regression for the `virtualmedia.*` row contract (DB向Def看齐):
/// canonical short field names match the SettingDef suffixes
/// (`crossDragStrategy`, `dualTimeSync`, ...). Legacy `vm*` rows migrate
/// forward once and are never written again.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqlite3Loaded();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  setUpAll(() async {
    await DbModule.init(AppDatabase(NativeDatabase.memory()));
  });

  test('cross-drag strategy updates live + round-trips at startup', () async {
    useAppStore();
    await useAppStore().initialized;

    await useAppStore().updateVmCrossSegmentDragStrategy(
        VmCrossSegmentDragStrategy.previewOnRelease);

    // Live state (the slider reads AppState, not VmPrefs).
    expect(useAppStore().state.vmCrossSegmentDragStrategy,
        VmCrossSegmentDragStrategy.previewOnRelease);

    // Persisted under the canonical Def-suffixed field.
    final rows = await DbModule.metaSettingsRepo.loadRawValues();
    expect(rows['virtualmedia.crossDragStrategy'], 'previewOnRelease');

    final reloaded = await useAppStore().applyVirtualMediaRows(
      const AppState(
          vmCrossSegmentDragStrategy: VmCrossSegmentDragStrategy.directSwitch),
    );
    expect(reloaded.vmCrossSegmentDragStrategy,
        VmCrossSegmentDragStrategy.previewOnRelease);
  });

  test('dual-time sync updates live + round-trips at startup', () async {
    useAppStore();
    await useAppStore().initialized;

    await useAppStore().updateVmDualTimeSync(VmDualTimeSyncMode.subToTotal);

    expect(useAppStore().state.vmDualTimeSync, VmDualTimeSyncMode.subToTotal);

    final rows = await DbModule.metaSettingsRepo.loadRawValues();
    expect(rows['virtualmedia.dualTimeSync'], 'subToTotal');

    final reloaded = await useAppStore().applyVirtualMediaRows(
      const AppState(vmDualTimeSync: VmDualTimeSyncMode.exact),
    );
    expect(reloaded.vmDualTimeSync, VmDualTimeSyncMode.subToTotal);
  });

  test('legacy vm* row migrates to the canonical short field once', () async {
    useAppStore();
    await useAppStore().initialized;

    // Seed ONLY the legacy row (no canonical row for markTickColor yet).
    await MetaSettingsModule.saveVirtualMediaRow(
        'vmMarkTickColor', '4278190335');

    final reloaded = await useAppStore().applyVirtualMediaRows(
      const AppState(),
    );
    expect(reloaded.vmMarkTickColor, 4278190335);

    // Migrated forward: canonical row now carries the value.
    final rows = await DbModule.metaSettingsRepo.loadRawValues();
    expect(rows['virtualmedia.markTickColor'], '4278190335');
  });

  test('canonical row wins over legacy when both present', () async {
    await MetaSettingsModule.saveVirtualMediaRow('vmMarkTickExtent', '9');
    await MetaSettingsModule.saveVirtualMediaRow('markTickExtent', '4');

    final reloaded = await useAppStore().applyVirtualMediaRows(
      const AppState(),
    );
    expect(reloaded.vmMarkTickExtent, 4);
  });

  test('VM prefs rehydrate even while legacy-storage persistence is ON',
      () async {
    // Switching legacy <-> meta storage must not lose VM prefs: the toggle
    // only disables the FEATURE surface, not the rehydration of saved rows.
    await MetaSettingsModule.saveVirtualMediaRow('dualTimeSync', 'exact');

    final reloaded = await useAppStore().applyVirtualMediaRows(
      const AppState(
        useLegacyStoragePersistence: true,
        vmDualTimeSync: VmDualTimeSyncMode.subToTotal,
      ),
    );
    expect(reloaded.vmDualTimeSync, VmDualTimeSyncMode.exact);
  });

  test('stored exact row survives the subToTotal default flip', () async {
    // The default change is fresh-install only: an existing user who chose
    // `exact` keeps it (no forced migration), even though the typed default
    // is now subToTotal.
    await MetaSettingsModule.saveVirtualMediaRow('dualTimeSync', 'exact');

    final reloaded = await useAppStore().applyVirtualMediaRows(
      const AppState(),
    );
    expect(reloaded.vmDualTimeSync, VmDualTimeSyncMode.exact);
  });
}
