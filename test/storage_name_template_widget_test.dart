import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/meta_settings/meta_settings_module.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/models/storages/storage_name_prefs.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_storage_store.dart';
import 'package:iris/widgets/dialogs/show_webdav_dialog.dart';

/// Storage-name template behaviour: order badges, live preview/hint, dedupe,
/// global-vs-session persistence, reset, and the non-focus-stealing chips.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  setUpAll(() async {
    await DbModule.init(AppDatabase(NativeDatabase.memory()));
  });

  Future<void> seedTemplate({
    String tags = 'type,account',
    String separator = '·',
    String enabled = '1',
  }) async {
    await MetaSettingsModule.persistAuxRow(StorageNamePrefs.tagsKey, tags);
    await MetaSettingsModule.persistAuxRow(
        StorageNamePrefs.separatorKey, separator);
    await MetaSettingsModule.persistAuxRow(
        StorageNamePrefs.enabledKey, enabled);
    await StorageNamePrefs.load();
  }

  setUp(() async {
    useAppStore();
    await useAppStore().initialized;
    final storageStore = useStorageStore();
    await storageStore.initialized;
    for (final storage in [...storageStore.state.storages]) {
      await storageStore.removeStorage(storage);
    }
    await seedTemplate();
  });

  Future<void> settleWrites(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 20));
  }

  Future<void> pumpDialog(
    WidgetTester tester, {
    WebDAVStorage? storage,
    List<Storage> extras = const <Storage>[],
  }) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    await tester.pumpWidget(
      StoreScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () {
                    for (final extra in extras) {
                      useStorageStore().addStorage(extra);
                    }
                    if (storage != null) {
                      useStorageStore().addStorage(storage);
                    }
                    showWebDAVDialog(context, storage: storage);
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  WebDAVStorage editStorage({String name = 'nas'}) => WebDAVStorage(
        id: 's1',
        name: name,
        host: 'nas.local',
        basePath: const <String>['/media/movies'],
        port: '5005',
        username: 'alice',
        password: 'secret',
        https: false,
      );

  testWidgets('lit order drives the preview and the chip badges',
      (tester) async {
    await pumpDialog(tester, storage: editStorage());

    expect(find.text('Preview: WebDAV·alice'), findsOneWidget);
    // Default type/account are badges 1 and 2.
    expect(find.text('1'), findsWidgets);
    expect(find.text('2'), findsWidgets);

    await tester.tap(find.widgetWithText(FilterChip, 'Host'));
    await tester.pump();
    expect(find.text('Preview: WebDAV·alice·nas.local'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'Path'));
    await tester.pump();
    expect(
      find.text('Preview: WebDAV·alice·nas.local·movies'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty name shows the composed deduped name as a hint',
      (tester) async {
    final existing = LocalStorage(
      id: 'other',
      type: StorageType.internal,
      name: 'WebDAV·alice',
      basePath: const <String>['/'],
    );
    await pumpDialog(
      tester,
      storage: editStorage(name: ''),
      extras: <Storage>[existing],
    );

    expect(find.text('WebDAV·alice (2)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('global ON persists template edits immediately, cancel keeps them',
      (tester) async {
    await pumpDialog(tester, storage: editStorage());

    await tester.tap(find.widgetWithText(FilterChip, 'Host'));
    await settleWrites(tester);

    var rows = await MetaSettingsModule.repo.loadRawValues();
    expect(rows[StorageNamePrefs.tagsKey], 'type,account,host');

    await tester.tap(find.text('Cancel'));
    await settleWrites(tester);

    rows = await MetaSettingsModule.repo.loadRawValues();
    expect(rows[StorageNamePrefs.tagsKey], 'type,account,host');
  });

  testWidgets('global OFF keeps edits in-session but never persists',
      (tester) async {
    await seedTemplate(enabled: '0');
    await pumpDialog(tester, storage: editStorage());

    await tester.tap(find.widgetWithText(FilterChip, 'Host'));
    await settleWrites(tester);

    expect(StorageNamePrefs.template.tags, contains(StorageNameTag.host));
    final rows = await MetaSettingsModule.repo.loadRawValues();
    expect(rows[StorageNamePrefs.tagsKey], 'type,account');
    expect(tester.takeException(), isNull);
  });

  testWidgets('reset restores the true defaults', (tester) async {
    await seedTemplate(tags: 'host,port', separator: '-', enabled: '1');
    await pumpDialog(tester, storage: editStorage());

    expect(find.text('Preview: nas.local-5005'), findsOneWidget);

    await tester.tap(find.text('Reset'));
    await settleWrites(tester);

    expect(find.text('Preview: WebDAV·alice'), findsOneWidget);
    final rows = await MetaSettingsModule.repo.loadRawValues();
    expect(rows[StorageNamePrefs.tagsKey], 'type,account');
    expect(rows[StorageNamePrefs.separatorKey], '·');
  });

  testWidgets('separator commits on blur, never per keystroke',
      (tester) async {
    await pumpDialog(tester, storage: editStorage());

    // The separator is the only field capped at maxSeparatorLength.
    final separator = find.byWidgetPredicate(
        (w) => w is TextField && w.maxLength == StorageNamePrefs.maxSeparatorLength);
    expect(separator, findsOneWidget);

    await tester.enterText(separator, '-');
    await settleWrites(tester);

    // Typing updates the session preview but must NOT touch storage.
    var rows = await MetaSettingsModule.repo.loadRawValues();
    expect(rows[StorageNamePrefs.separatorKey], '·',
        reason: 'per-keystroke write would block the UI isolate');

    // Leaving the field flushes it once.
    await tester.tap(find.byType(TextFormField).at(1));
    await settleWrites(tester);

    rows = await MetaSettingsModule.repo.loadRawValues();
    expect(rows[StorageNamePrefs.separatorKey], '-');
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a chip never steals focus from a text field',
      (tester) async {
    await pumpDialog(tester, storage: editStorage());

    await tester.tap(find.byType(TextFormField).at(1));
    await tester.pump();
    final before = FocusManager.instance.primaryFocus;
    expect(before, isNotNull);

    await tester.tap(find.widgetWithText(FilterChip, 'Host'));
    await tester.pump();

    expect(FocusManager.instance.primaryFocus, same(before));
  });

  testWidgets('template section stays overflow-free at 360 + keyboard + large font',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    await tester.pumpWidget(
      StoreScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () =>
                      showWebDAVDialog(context, storage: editStorage()),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
  });
}
