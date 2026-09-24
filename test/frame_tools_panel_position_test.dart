import 'package:drift/native.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/meta_settings/meta_settings_module.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_app_store.dart';

import 'helpers/sqlite3_loader.dart';

/// Persistence contract for the frame-tools float panel position.
///
/// The panel remembers WHERE it was parked, and it remembers it as a
/// FRACTION of the host box rather than pixels — an absolute offset drifts as
/// soon as the window resizes. These cases cover the two halves of that:
/// clamping on the way in, and rehydrating from the `screenshot.` AUX row.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqlite3Loaded();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  setUpAll(() async {
    final db = AppDatabase(NativeDatabase.memory());
    await DbModule.init(db);
  });

  test('an out-of-range fraction is clamped into the host box', () async {
    await useAppStore()
        .updateFrameToolsPanelFraction(const Offset(1.4, -0.3));
    expect(useAppStore().state.frameToolsPanelFraction,
        const Offset(1, 0), reason: 'a stored value must never park it outside');
  });

  test('the fraction round-trips through the screenshot AUX row', () async {
    const Offset parked = Offset(0.75, 0.9);
    await useAppStore().updateFrameToolsPanelFraction(parked);

    final Map<String, String> rows =
        await MetaSettingsModule.loadScreenshotRows();
    expect(rows['frameToolsOffset'], isNotNull,
        reason: 'the position must reach the screenshot. domain');

    // Rehydrate onto a DEFAULTED state, so anything non-default can only have
    // come from the row — this is the actual restart path.
    final AppState revived = await useAppStore()
        .applyScreenshotRows(const AppState());
    expect(revived.frameToolsPanelFraction, parked,
        reason: 'a restart must restore the same relative spot');
  });

  test('a malformed row degrades to the centred default', () async {
    await MetaSettingsModule.saveScreenshotRow(
        'frameToolsOffset', '"not-a-pair"');
    final AppState revived =
        await useAppStore().applyScreenshotRows(const AppState());
    expect(revived.frameToolsPanelFraction,
        const AppState().frameToolsPanelFraction,
        reason: 'a corrupt row must not strand the panel off-screen');
  });

  test('the default placement is horizontally centred', () {
    // The very first reveal (nothing remembered yet) must land mid-screen,
    // which a 0.5 horizontal fraction guarantees at ANY host width.
    expect(const AppState().frameToolsPanelFraction.dx, 0.5);
  });
}
