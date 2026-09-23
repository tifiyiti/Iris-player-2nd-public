import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/view/files_db_paging/storage_browser_data_source.dart';
import 'package:iris/features/paginated_browser/models/generic_browser_models.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/store/use_storage_store.dart';
import 'package:iris/utils/get_localizations.dart';

// Folder rows in the storagedb file page expose "Scan recursively" in
// their trailing more-action menu; plain files do not.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  setUpAll(() async {
    await DbModule.init(AppDatabase(NativeDatabase.memory()));
    usePlayQueueStore();
    await usePlayQueueStore().initialized;
    useAppStore();
    await useAppStore().initialized;
    useStorageStore();
    await useStorageStore().initialized;
  });

  Storage testStorage() => Storage.local(
        id: 'scan-action-test',
        type: StorageType.internal,
        name: 't',
        basePath: const ['root'],
      );

  FileItem dirItem() => const FileItem(
        storageId: 'scan-action-test',
        name: 'sub',
        uri: 'sub',
        path: ['root', 'sub'],
        isDir: true,
        type: ContentType.other,
      );

  FileItem fileItem() => const FileItem(
        storageId: 'scan-action-test',
        name: 'v.mp4',
        uri: 'v.mp4',
        path: ['root', 'v.mp4'],
        type: ContentType.video,
      );

  Future<List<GenericItemAction<FileItem>>> trailingFor(
    WidgetTester tester,
    Storage storage,
    FileItem item,
  ) async {
    late List<GenericItemAction<FileItem>> actions;
    late String scanLabel;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(builder: (context) {
          scanLabel = getLocalizations(context).files_scan_recursive;
          actions = StorageBrowserDataSource(storage)
              .getItemTrailingActions(context, item);
          return const SizedBox();
        }),
      ),
    ));
    await tester.pumpAndSettle();
    expect(scanLabel, isNotEmpty);
    return actions;
  }

  testWidgets('dir trailing contains scan recursively', (tester) async {
    final storage = testStorage();
    final actions = await trailingFor(tester, storage, dirItem());
    expect(
      actions.any((a) => a.label == getScanLabel(tester)),
      isTrue,
      reason: 'dir trailing should offer Scan recursively',
    );
  });

  testWidgets('file trailing has no scan recursively', (tester) async {
    final storage = testStorage();
    final actions = await trailingFor(tester, storage, fileItem());
    expect(
      actions.any((a) => a.label == getScanLabel(tester)),
      isFalse,
      reason: 'plain file trailing must not offer Scan recursively',
    );
  });

  testWidgets('dir scan is disabled offline', (tester) async {
    final storage = testStorage();
    useStorageStore().markDisconnected(storage.id);
    try {
      final actions = await trailingFor(tester, storage, dirItem());
      final scan =
          actions.where((a) => a.label == getScanLabel(tester)).toList();
      expect(scan, hasLength(1));
      expect(scan.single.enabled, isFalse);
    } finally {
      useStorageStore().markConnected(storage.id);
    }
  });
}

String getScanLabel(WidgetTester tester) {
  final ctx = tester.element(find.byType(Scaffold));
  return getLocalizations(ctx).files_scan_recursive;
}
