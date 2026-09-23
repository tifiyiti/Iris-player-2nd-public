import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/view/content/data_source/lib_content_data_source.dart';
import 'package:iris/features/media_library/view/content/model/lib_content_item.dart';
import 'package:iris/features/media_library/view/content/store/media_lib_content_runtime_state.dart';
import 'package:iris/features/media_library/view/content/store/use_media_lib_content_store.dart';
import 'package:iris/features/media_library/view/tab/store/libs/enum/load_state.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_storage_store.dart';

/// The page rebuilds from this data source; a store emission whose page-visible
/// snapshot is unchanged must be swallowed so one user action does not rebuild
/// the list twice for the same pixels.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  setUpAll(() async {
    await DbModule.init(AppDatabase(NativeDatabase.memory()));
    useAppStore();
    await useAppStore().initialized;
    useStorageStore();
    await useStorageStore().initialized;
    useMediaLibContentStore();
    await useMediaLibContentStore().initialized;
  });

  test('no-op store emission does not notify the page', () async {
    final store = useMediaLibContentStore();
    final ds = LibContentDataSource(store);
    addTearDown(ds.dispose);

    var notifications = 0;
    ds.addListener(() => notifications++);

    // A store emission that changes nothing the page renders is swallowed.
    store.debugEmitNoop();
    await Future<void>.delayed(Duration.zero);
    expect(notifications, 0,
        reason: 'an identical runtime snapshot must not rebuild the page');

    // A real change (items/total) must notify.
    store.debugSetRuntime(const MediaLibContentRuntimeState(
      state: LoadState.ready,
      items: <LibContentItem>[],
      totalItems: 7,
      totalPages: 3,
      currentPage: 1,
    ));
    await Future<void>.delayed(Duration.zero);
    expect(notifications, 1, reason: 'a real page change must reach the page');
  });
}
