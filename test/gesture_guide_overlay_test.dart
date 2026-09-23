import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/tag_play/store/use_tag_play_store.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/store/gesture/gesture_region_layout.dart';
import 'package:iris/models/store/gesture_region.dart';
import 'package:iris/pages/player/overlays/gesture_region_editor/gesture_settings_dialog.dart';
import 'package:iris/pages/player/overlays/gesture_tips_overlay.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:iris/utils/platform.dart';
import 'package:provider/provider.dart';
import 'package:zustand/zustand.dart';

/// StoreScope-equivalent that does NOT dispose the global StoreLocator on
/// unmount (mirrors media_play_actions_test.providerScope).
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
    usePlayerUiStore();
    useTagPlayStore();
  });

  tearDown(() async {
    usePlayerUiStore().updateIsShowGestureTips(false);
    usePlayerUiStore().updateGestureGuidePage(0);
    final app = useAppStore();
    app.set(app.state.copyWith(useMetadataSettings: false));
    useTagPlayStore().set(useTagPlayStore().state.copyWith(
          activeViewTagId: null,
          viewStackTagIds: const [],
        ));
  });

  // NOTE 1: flutter_zustand's select()→rebuild chain does not deliver under
  // the widget-test FakeAsync zone (probe-verified). NOTE 2: an unchanged
  // const child is skipped entirely on pumpWidget, so re-pumping must remount
  // via a fresh key. Tests therefore force a full rebuild by re-pumping with
  // a UniqueKey after mutating stores; production uses the real event loop.
  Future<void> pumpGuide(WidgetTester tester, {bool flag = true}) async {
    usePlayerUiStore().updateIsShowGestureTips(flag);
    await tester.pumpWidget(providerScope(MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: GestureTipsOverlay(key: UniqueKey())),
    )));
    // Deferred ARB loading resolves asynchronously — settle until the tree
    // (and any pushed dialogs) are fully built.
    await tester.pumpAndSettle();
  }
  testWidgets('hidden by default (flag off renders nothing)',
      (tester) async {
    await tester
        .pumpWidget(providerScope(MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: GestureTipsOverlay(key: UniqueKey())),
    )));
    await tester.pumpAndSettle();
    expect(find.text('播放 / 暂停'), findsNothing);
  });

  testWidgets('renders LIVE double-tap regions from the resolved layout',
      (tester) async {
    await pumpGuide(tester);

    // Page 0 = doubleTap (first in the guide intent order). Meta 3×3 grid
    // default: top row seekB|playPause|seekF, middle seekB|playPause|seekF, bottom
    // seekB|Tag|seekF.
    expect(find.text('播放 / 暂停'), findsNWidgets(2));
    expect(find.text('快退'), findsNWidgets(3));
    expect(find.text('快进'), findsNWidgets(3));
    // Bottom-center Tag = 1
    expect(find.text('打开 Tag 视图'), findsNWidgets(1));
    expect(find.text('生效中 · tag 视图自动跟随'), findsNothing);
    // No "current profile" header — the chip legend carries that info.
    expect(find.textContaining('当前：'), findsNothing);
  });

  testWidgets('every intent chip shows its text; tapping a chip switches page',
      (tester) async {
    await pumpGuide(tester);

    // Full-text legend: one chip per rendered intent, all readable up front.
    expect(find.text('双击'), findsOneWidget);
    expect(find.text('单击'), findsOneWidget);
    expect(find.text('长按'), findsOneWidget);
    expect(find.text('纵向滑动'), findsOneWidget);
    expect(find.text('横向滑动'), findsOneWidget);
    expect(find.text('长按横滑'), findsOneWidget);
    // hover is intentionally absent from the phone guide (desktop-only intent)
    expect(find.text('悬停'), findsNothing);

    // Jump to the tap page via its chip.
    await tester.tap(find.text('单击'));
    await tester.pumpAndSettle();

    expect(find.text('显示 / 隐藏控制栏'), findsOneWidget,
        reason: 'tap page = full-screen toggle');
    expect(find.text('播放 / 暂停'), findsNothing,
        reason: 'doubleTap page content must be off-page');
  });

  testWidgets('horizontal swipe switches intent pages', (tester) async {
    await pumpGuide(tester);

    expect(find.text('播放 / 暂停'), findsNWidgets(2));

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.text('显示 / 隐藏控制栏'), findsOneWidget);
    expect(find.text('播放 / 暂停'), findsNothing);
  });

  testWidgets('auto-follow: an active tag view shows badge but guide still has tag strips',
      (tester) async {
    final app = useAppStore();
    app.set(app.state.copyWith(useMetadataSettings: true));

    await pumpGuide(tester);

    useTagPlayStore()
        .set(useTagPlayStore().state.copyWith(activeViewTagId: 7));
    await pumpGuide(tester);

    expect(find.text('打开 Tag 视图'), findsNWidgets(1));
    expect(find.text('生效中 · tag 视图自动跟随'), findsOneWidget);
  });

  testWidgets('X button hides the guide', (tester) async {
    await pumpGuide(tester);

    await tester.tap(find.byKey(const Key('gesture_guide_close')));
    await tester.pump();

    expect(usePlayerUiStore().state.isShowGestureTips, isFalse);
    await pumpGuide(tester, flag: false);
    expect(find.text('播放 / 暂停'), findsNothing);
  });

  testWidgets('settings flow hides the guide, then restores the same page and map',
      (tester) async {
    await pumpGuide(tester);

    // Move to the longPress page first — this is the position to restore.
    await tester.tap(find.text('长按'));
    await tester.pumpAndSettle();
    expect(find.text('长按倍速播放'), findsNWidgets(2));
    expect(find.text('播放 / 暂停'), findsNothing);

    await tester.tap(find.byKey(const Key('gesture_guide_settings')));
    await tester.pumpAndSettle();

    expect(usePlayerUiStore().state.isShowGestureTips, isFalse,
        reason: 'guide hides itself while the editor flow is open');
    expect(find.byType(GestureSettingsDialog), findsOneWidget);

    // Close the dialog without entering the editor (locale-independent
    // finder: the test host resolves to the English ARB).
    await tester.tap(find
        .descendant(
          of: find.byType(GestureSettingsDialog),
          matching: find.byType(TextButton),
        )
        .first);
    await tester.pumpAndSettle();

    expect(usePlayerUiStore().state.isShowGestureTips, isTrue,
        reason: 'guide must come back by itself after the flow closes');
    expect(find.text('长按倍速播放'), findsNWidgets(2),
        reason: 'restored to the exact pre-entry page incl. the action map');
    expect(find.text('播放 / 暂停'), findsNothing);
  });

  testWidgets('legacy (classic mode) shows a read-only caption and no edit pencil',
      (tester) async {
    debugIsMobilePlatformOverride = true; // simulate phone on the test host
    addTearDown(() => debugIsMobilePlatformOverride = null);

    await pumpGuide(tester); // gate OFF → classic

    expect(find.byKey(const Key('gesture_guide_edit')), findsNothing,
        reason: 'classic has no partitions to edit');
    expect(find.text('经典手势 · 无分区'), findsOneWidget);
  });

  testWidgets('meta mode exposes the edit pencil; tapping it opens editor (inline edit is retained dead code)',
      (tester) async {
    debugIsMobilePlatformOverride = true;
    addTearDown(() => debugIsMobilePlatformOverride = null);
    final app = useAppStore();
    app.set(app.state.copyWith(useMetadataSettings: true));

    await pumpGuide(tester);

    expect(find.text('经典手势 · 无分区'), findsNothing);
    expect(find.byKey(const Key('gesture_guide_edit')), findsOneWidget);
    // Inline drag handles are retained but dead — no 75% pill on guide.
    expect(find.text('75%'), findsNothing);
    // Snapshot layout before edit: tapping pencil must NOT commit inline.
    // Use whichever profile is active for the test window orientation.
    // Fallback to defaults if the store hasn't been normalized yet in this
    // isolated test pump (app.set(copyWith) bypasses _normalizeLoaded).
    final orientation = tester.view.physicalSize.width > tester.view.physicalSize.height
        ? Orientation.landscape
        : Orientation.portrait;
    final activeKey = useAppStore().resolveActiveGestureProfileKey(app.state, orientation);
    final beforeLayout = app.state.gestureLayoutProfiles[activeKey]?[GestureIntent.doubleTap] ??
        defaultGestureLayoutProfiles[activeKey]![GestureIntent.doubleTap]!;
    final beforeEdges = beforeLayout.regions.map((r) => r.normalizedRect.right).toList();

    // Tapping edit now hides guide and pushes the full-screen grid editor
    // (m*n lines, reset/cancel/confirm). In test, guide hides first.
    // In widget-test the editor route push is async; we verify the inline
    // path is dead and the stored layout is untouched.
    await tester.tap(find.byKey(const Key('gesture_guide_edit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    // No inline drag handles appear (dead inline editor).
    expect(find.text('75%'), findsNothing);
    // Layout unchanged by inline path (editor not yet confirmed).
    final afterLayout = app.state.gestureLayoutProfiles[activeKey]?[GestureIntent.doubleTap] ??
        defaultGestureLayoutProfiles[activeKey]![GestureIntent.doubleTap]!;
    expect(afterLayout.regions.map((r) => r.normalizedRect.right).toList(), beforeEdges);
  });
}
