import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/store/use_storage_store.dart';

import 'helpers/sqlite3_loader.dart';

/// Regression: AppStore is constructed on the first frame (before the DB is
/// wired). Its `onReady` must stay synchronous so widget tests under FakeAsync
/// do not deadlock; the backend switch happens explicitly afterwards via
/// [AppStore.applyConfiguredBackends].
void main() {
  ensureSqlite3Loaded();
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  late AppDatabase db;

  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory());
    await DbModule.init(db);
  });

  tearDownAll(() => db.close());

  test('applyConfiguredBackends switches storage + queue to query mode',
      () async {
    final app = useAppStore();
    await app.initialized;
    app.set(app.state.copyWith(useLegacyStoragePersistence: false));

    await app.applyConfiguredBackends();

    expect(useStorageStore().isUsingLegacy, isFalse);
    expect(usePlayQueueStore().isQueryMode, isTrue);
  });

  test('applyConfiguredBackends switches back to legacy mode', () async {
    final app = useAppStore();
    await app.initialized;
    app.set(app.state.copyWith(useLegacyStoragePersistence: true));

    await app.applyConfiguredBackends();

    expect(useStorageStore().isUsingLegacy, isTrue);
    expect(usePlayQueueStore().isQueryMode, isFalse);
  });
}
