import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/app_identity/model/domain/app_identity_entry.dart';
import 'package:iris/features/app_identity/view/app_identity_manager_dialog.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:provider/provider.dart';
import 'package:zustand/zustand.dart';

import 'helpers/sqlite3_loader.dart';

/// StoreScope-equivalent that does NOT dispose the global StoreLocator on
/// unmount (mirrors frame_tools_float_panel_test.providerScope).
Widget providerScope(Widget child) {
  return InheritedProvider<StoreLocator>.value(
    value: StoreLocator(),
    startListening: (InheritedContext<StoreLocator?> e, StoreLocator value) {
      final sub = value.changes.listen((_) => e.markNeedsNotifyDependents());
      return sub.cancel;
    },
    lazy: false,
    child: child,
  );
}

/// Regression coverage for the custom-entry editor, opened through its real
/// entry point ([openAppIdentityEditor]) so the canonical keyboard shell is
/// exercised: 360px sheet and desktop dialog stay overflow-free at 1.3x text,
/// focusing the name field never hides the image picker, and the sheet cannot
/// be swipe/scrim/X-dismissed — Cancel is the only way out.
void main() {
  ensureSqlite3Loaded();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  late AppDatabase moduleDb;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async => null);
    moduleDb = AppDatabase(NativeDatabase.memory());
    await DbModule.init(moduleDb);
  });
  tearDownAll(() => moduleDb.close());

  Widget app(Widget child) {
    return providerScope(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );
  }

  Widget opener({AppIdentityEntry? existing}) {
    return Builder(
      builder: (context) => Center(
        child: TextButton(
          onPressed: () => openAppIdentityEditor(context, existing: existing),
          child: const Text('open'),
        ),
      ),
    );
  }

  Future<void> openEditor(
    WidgetTester tester, {
    AppIdentityEntry? existing,
    Size surface = const Size(360, 700),
  }) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    await tester.pumpWidget(app(opener(existing: existing)));
    await tester.pump();
    // Deferred l10n delegates load async — settle before tapping the opener.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> focusNameField(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const ValueKey('entryNameField')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('entryNameField')));
    await tester.pumpAndSettle();
  }

  testWidgets('360px sheet opens with no overflow (independent default)',
      (tester) async {
    await openEditor(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byKey(const ValueKey('entryNameField')), findsOneWidget);
    // Independent is the default → seed selectors are shown.
    expect(find.byKey(const ValueKey('entrySeedScenario')), findsOneWidget);
    expect(find.byKey(const ValueKey('entrySeedTag')), findsOneWidget);
  });

  testWidgets('desktop dialog opens with no overflow', (tester) async {
    await openEditor(tester, surface: const Size(1024, 800));
    expect(tester.takeException(), isNull);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byKey(const ValueKey('entryNameField')), findsOneWidget);
  });

  testWidgets('shared mode hides the initial scenario/tag selectors',
      (tester) async {
    await openEditor(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('entryModeShared')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('entryModeShared')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('entrySeedScenario')), findsNothing);
    expect(find.byKey(const ValueKey('entrySeedTag')), findsNothing);
  });

  testWidgets('keyboard frames do not rebuild the form', (tester) async {
    var builds = 0;
    EntryEditorForm.debugOnFormBuild = () => builds++;
    addTearDown(() => EntryEditorForm.debugOnFormBuild = null);

    await openEditor(tester);
    expect(tester.takeException(), isNull);

    // Only keyboard height changes now — the cached form must not rebuild.
    builds = 0;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(builds, 0);
    expect(find.byKey(const ValueKey('entryNameField')), findsOneWidget);
  });

  testWidgets('save stays disabled until an image is chosen (create mode)',
      (tester) async {
    await openEditor(tester);
    await focusNameField(tester);
    await tester.enterText(
      find.byKey(const ValueKey('entryNameField')),
      'My Entry',
    );
    await tester.pump();
    final save = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(save.onPressed, isNull);
    expect(find.text('请先选择图片后再保存。'), findsOneWidget);
  });

  testWidgets('editing a name-only entry now requires an image',
      (tester) async {
    await openEditor(
      tester,
      existing: AppIdentityEntry(id: 'e2', name: 'NameOnly'),
    );
    final save = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(save.onPressed, isNull);
    expect(find.text('请先选择图片后再保存。'), findsOneWidget);
  });

  testWidgets('editing an entry with an existing icon can save without re-pick',
      (tester) async {
    await openEditor(
      tester,
      existing: AppIdentityEntry(
        id: 'e1',
        name: 'WithIcon',
        imageRef: 'identity/entry_e1_v1.png',
      ),
    );
    final save = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(save.onPressed, isNotNull);
    expect(find.text('请先选择图片后再保存。'), findsNothing);
  });

  testWidgets('stale seed scenario is dropped without asserting',
      (tester) async {
    await openEditor(
      tester,
      existing: AppIdentityEntry(
        id: 'e3',
        name: 'StaleScenario',
        imageRef: 'identity/entry_e3_v1.png',
        seedScenarioId: 'deleted-scenario',
      ),
    );
    // A dangling id must never reach DropdownButtonFormField's value (that
    // throws a debug assertion); it renders as the "none" choice instead.
    expect(tester.takeException(), isNull);
    expect(find.text('— 无 —'), findsWidgets);
  });

  testWidgets('stale seed tag is dropped without asserting', (tester) async {
    await openEditor(
      tester,
      existing: AppIdentityEntry(
        id: 'e4',
        name: 'StaleTag',
        imageRef: 'identity/entry_e4_v1.png',
        seedTagId: 999999,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('focusing the name field keeps the image picker mounted',
      (tester) async {
    await openEditor(tester);
    expect(find.text('选择图片'), findsOneWidget);

    await focusNameField(tester);
    // Simulate the software keyboard: the body shrinks but must never drop the
    // picker (the old folding chrome removed it entirely).
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('选择图片'), findsOneWidget);
  });

  testWidgets('swipe-down does not dismiss the editor', (tester) async {
    await openEditor(tester);
    expect(find.byKey(const ValueKey('entryNameField')), findsOneWidget);

    await tester.drag(find.byType(BottomSheet), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('entryNameField')), findsOneWidget);
  });

  testWidgets('no close (X) button; only Cancel leaves the editor',
      (tester) async {
    await openEditor(tester);
    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.text('取消'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('entryNameField')), findsNothing);
  });
}
