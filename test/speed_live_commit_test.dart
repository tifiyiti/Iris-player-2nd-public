import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/meta_settings/meta_settings_module.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/store/use_app_store.dart';

import 'helpers/sqlite3_loader.dart';

/// Held X/C keys drive the rate live (~30×/s) and must not hit storage on
/// every auto-repeat; the KeyUp path flushes once through [AppStore.commitRate].
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqlite3Loaded();

  late AppDatabase db;

  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory());
    await DbModule.init(db);
  });
  tearDownAll(() => db.close);

  setUp(() async {
    await MetaSettingsModule.repo.clearValues();
  });

  test('updateRateLive refreshes memory without persisting', () async {
    final store = useAppStore();
    await store.initialized;

    store.updateRateLive(1.7);
    expect(store.state.rate, 1.7);
    expect(store.state.rateBeforeReset, 1.7);

    final raw = await MetaSettingsModule.repo.loadRawValues();
    expect(raw.containsKey('app.rate'), isFalse,
        reason: 'live update must not write storage');
  });

  test('commitRate flushes the pending live rate once', () async {
    final store = useAppStore();
    await store.initialized;

    store.updateRateLive(2.3);
    await store.commitRate();

    final raw = await MetaSettingsModule.repo.loadRawValues();
    expect(double.parse(raw['app.rate']!), closeTo(2.3, 1e-9));

    // Second commit is a clean no-op (dirty flag already cleared).
    await store.commitRate();
  });

  test('commitRate is a no-op when nothing was updated live', () async {
    final store = useAppStore();
    await store.initialized;

    await store.commitRate();

    final raw = await MetaSettingsModule.repo.loadRawValues();
    expect(raw.containsKey('app.rate'), isFalse);
  });
}
