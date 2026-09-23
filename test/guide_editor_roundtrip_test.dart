import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/phone/gesture_guide/view/gesture_guide_overlay.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/pages/player/overlays/gesture_tips_overlay.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:iris/store/warning_dialogs.dart';
// Test-only StoreLocator host (see pubspec dev_dependencies comment).
import 'package:zustand/zustand.dart';
import 'package:provider/provider.dart';

/// Requirement #4: guide → settings dialog → full-screen editor → back
/// arrow must land BACK ON THE GUIDE (re-shown, same page) — and the system
/// back arrow must behave identically from the editor route.
void main() {
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

  Future<void> pumpGuide(WidgetTester tester) async {
    await tester.pumpWidget(providerScope(MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: GestureTipsOverlay()),
    )));
    // Deferred ARB loading resolves asynchronously — settle until the tree
    // (and any pushed dialogs/routes) are fully built.
    await tester.pumpAndSettle();
  }

  testWidgets('guide → settings → editor → back arrow returns to the guide',
      (tester) async {
    usePlayerUiStore().updateIsShowGestureTips(true);
    addTearDown(() => usePlayerUiStore().updateIsShowGestureTips(false));
    // Ensure cancel warning is shown (not suppressed) so the test exercises
    // the new reset/cancel/confirm suppressible flow.
    await useAppStore().resetWarning(kWarningGestureEditCancel);
    await useAppStore().resetWarning(kWarningGestureEditReset);
    await useAppStore().resetWarning(kWarningGestureEditConfirm);

    await pumpGuide(tester);
    expect(find.text('播放 / 暂停'), findsWidgets,
        reason: 'guide is open on the doubleTap page');

    // Gear → settings dialog (guide hides itself for the round-trip).
    await tester.tap(find.byKey(const Key('gesture_guide_settings')));
    await tester.pumpAndSettle();
    expect(usePlayerUiStore().state.isShowGestureTips, isFalse);

    // Confirm the edit selection (the dialog's action row: Cancel is a
    // TextButton, Edit is an ElevatedButton).
    final editButton = find.byType(ElevatedButton);
    expect(editButton, findsOneWidget);
    await tester.tap(editButton);
    await tester.pumpAndSettle();

    // Full-screen editor route is now on top.
    expect(find.byKey(const Key('gesture_guide_settings')), findsNothing,
        reason: 'guide is covered by the editor route');
    expect(find.byIcon(Icons.arrow_back), findsOneWidget,
        reason: 'the editor bar closes via a BACK arrow (requirement #4)');

    // Press the editor's back arrow → shows cancel warning → confirm "放弃" → pops → guide re-shows.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    // The editor's cancel is now a suppressible warning ("不再提示").
    final cancelConfirm = find.text('放弃');
    if (cancelConfirm.evaluate().isNotEmpty) {
      await tester.tap(cancelConfirm);
      await tester.pumpAndSettle();
    }

    expect(usePlayerUiStore().state.isShowGestureTips, isTrue,
        reason: 'guide must come back by itself after the editor closes');
    expect(find.text('播放 / 暂停'), findsWidgets,
        reason: 'restored to the pre-entry page');
  });

  testWidgets('system back arrow from the editor also returns to the guide',
      (tester) async {
    usePlayerUiStore().updateIsShowGestureTips(true);
    addTearDown(() => usePlayerUiStore().updateIsShowGestureTips(false));
    await useAppStore().resetWarning(kWarningGestureEditCancel);

    await pumpGuide(tester);
    await tester.tap(find.byKey(const Key('gesture_guide_settings')));
    await tester.pumpAndSettle();
    final editButton = find.byType(ElevatedButton);
    await tester.tap(editButton);
    await tester.pumpAndSettle();

    // Simulate the Android system back arrow on the editor route.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    // System back also goes through the same suppressible cancel warning.
    final sysCancelConfirm = find.text('放弃');
    if (sysCancelConfirm.evaluate().isNotEmpty) {
      await tester.tap(sysCancelConfirm);
      await tester.pumpAndSettle();
    }

    expect(usePlayerUiStore().state.isShowGestureTips, isTrue,
        reason: 'popping the editor via system back re-shows the guide');
    expect(find.text('播放 / 暂停'), findsWidgets,
        reason: 'guide is open on the doubleTap page');
  });
}
