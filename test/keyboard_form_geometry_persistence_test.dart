import 'package:drift/native.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/meta_settings/meta_settings_module.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/models/store/keyboard_form_geometry.dart';
import 'package:iris/store/use_app_store.dart';

import 'helpers/sqlite3_loader.dart';

/// Persistence contract for the keyboard form's remembered geometry.
///
/// Mirrors the speed picker card: WHERE the form sits and HOW WIDE it is, both
/// stored as FRACTIONS rather than pixels, because a pixel value drifts the
/// moment the window resizes or the device rotates. Covers clamping on the way
/// in, the round-trip through the `form.` AUX row, and the fallback for a
/// corrupt row.
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

  test('the default geometry is centred at the auto width', () {
    final AppState fresh = const AppState();
    expect(fresh.keyboardFormGeometry.offset, const Offset(0.5, 0.5));
    expect(fresh.keyboardFormGeometry.widthFraction, isNull,
        reason: 'null means "size me to the viewport", not a stored width');
  });

  test('an out-of-range fraction is clamped into the travel', () async {
    await useAppStore().updateKeyboardFormGeometry(
      const KeyboardFormGeometry(
        offset: Offset(1.4, -0.3),
        widthFraction: 5.0,
      ),
    );
    final KeyboardFormGeometry stored =
        useAppStore().state.keyboardFormGeometry;
    expect(stored.offset, const Offset(1, 0),
        reason: 'a stored value must never park the form outside its travel');
    expect(stored.widthFraction, 1.0);
  });

  test('the geometry round-trips through the form AUX row', () async {
    const KeyboardFormGeometry parked =
        KeyboardFormGeometry(offset: Offset(0.2, 0.85), widthFraction: 0.4);
    await useAppStore().updateKeyboardFormGeometry(parked);

    final Map<String, String> rows = await MetaSettingsModule.loadFormRows();
    expect(rows['geometry'], isNotNull,
        reason: 'the geometry must reach the form. domain');

    // Rehydrate onto a DEFAULTED state, so anything non-default can only have
    // come from the row — this is the actual restart path.
    final AppState revived =
        await useAppStore().applyFormRows(const AppState());
    expect(revived.keyboardFormGeometry, parked,
        reason: 'a restart must restore the same relative box');
  });

  test('a malformed row degrades to the centred default', () async {
    await MetaSettingsModule.saveFormRow('geometry', '"not-a-triple"');
    final AppState revived =
        await useAppStore().applyFormRows(const AppState());
    expect(revived.keyboardFormGeometry,
        const AppState().keyboardFormGeometry,
        reason: 'a corrupt row must not strand the form off-screen');
  });

  test('an out-of-range stored width degrades instead of failing', () async {
    await MetaSettingsModule.saveFormRow('geometry', '0.5,0.5,9.0');
    final AppState revived =
        await useAppStore().applyFormRows(const AppState());
    expect(revived.keyboardFormGeometry.widthFraction, 1.0);
  });
}
