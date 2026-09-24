import 'package:drift/native.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/meta_settings/meta_settings_module.dart';
import 'package:iris/features/speed/model/enum/speed_rate_picker_mode.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_app_store.dart';

import 'helpers/sqlite3_loader.dart';

/// Persistence contract for the speed picker card's position.
///
/// The card remembers WHERE it was parked, as a FRACTION of the travel it has
/// rather than pixels — a pixel offset drifts as soon as the window resizes.
/// These cases cover clamping on the way in, rehydrating from the `speed.`
/// AUX row, and the fallback for a `rateMode` that no longer exists.
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

  test('an out-of-range fraction is clamped into the travel', () async {
    await useAppStore().updateSpeedRateDialogOffset(const Offset(1.4, -0.3));
    expect(useAppStore().state.speedRateDialogOffset, const Offset(1, 0),
        reason: 'a stored value must never park the card outside its travel');
  });

  test('the fraction round-trips through the speed AUX row', () async {
    const Offset parked = Offset(0.2, 0.85);
    await useAppStore().updateSpeedRateDialogOffset(parked);

    final Map<String, String> rows =
        await MetaSettingsModule.loadSpeedRows();
    expect(rows['dialogOffset'], isNotNull,
        reason: 'the position must reach the speed. domain');

    // Rehydrate onto a DEFAULTED state, so anything non-default can only have
    // come from the row — this is the actual restart path.
    final AppState revived =
        await useAppStore().applySpeedRows(const AppState());
    expect(revived.speedRateDialogOffset, parked,
        reason: 'a restart must restore the same relative spot');
  });

  test('a malformed row degrades to the centred default', () async {
    await MetaSettingsModule.saveSpeedRow('dialogOffset', '"not-a-pair"');
    final AppState revived =
        await useAppStore().applySpeedRows(const AppState());
    expect(revived.speedRateDialogOffset,
        const AppState().speedRateDialogOffset,
        reason: 'a corrupt row must not strand the card off-screen');
  });

  test('the default placement is centred', () {
    expect(const AppState().speedRateDialogOffset, const Offset(0.5, 0.5));
  });

  test('a rateMode that no longer exists degrades instead of failing',
      () async {
    // The comparison variants were pruned; anyone who had selected one is
    // still holding that string in their AUX row.
    await MetaSettingsModule.saveSpeedRow('rateMode', 'ruler');
    final AppState revived =
        await useAppStore().applySpeedRows(const AppState());
    expect(revived.speedRatePickerMode, SpeedRatePickerMode.dualWheel,
        reason: 'an unknown rateMode must keep the default, never blow up');
  });
}
