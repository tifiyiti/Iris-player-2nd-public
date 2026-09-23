import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/globals.dart' show moreMenuKeyNotifier;
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/control_bar/control_bar_widgets/more_menu_button.dart';
import 'package:iris/features/playback_tools/store/playback_tools_store.dart';
import 'package:iris/utils/platform.dart';
import 'package:provider/provider.dart';
// Test-only StoreLocator host (see pubspec dev_dependencies comment).
import 'package:zustand/zustand.dart';

/// StoreScope-equivalent that does NOT dispose the global StoreLocator on
/// unmount (mirrors gesture_guide_overlay_test.providerScope).
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

/// Regression: the phone-only playback-tools entries used context.select()
/// inside PopupMenuButton.itemBuilder — executed during the tap gesture, NOT
/// inside build — so provider's assertion fired on every more-button tap and
/// the menu never opened on Android (device log 2026-08: 6× identical
/// "Tried to use `context.select` outside of the `build` method").
void main() {
  setUp(() {
    debugIsMobilePlatformOverride = true;
    usePlaybackToolsStore().hideFrameTools();
  });

  tearDown(() {
    debugIsMobilePlatformOverride = null;
  });

  Future<void> pumpButton(WidgetTester tester) async {
    final player = MediaPlayer(
      isInitializing: false,
      isPlaying: false,
      externalSubtitles: const [],
      position: Duration.zero,
      duration: const Duration(minutes: 1),
      buffer: Duration.zero,
      width: 0,
      height: 0,
      saveProgress: () async {},
      play: () async {},
      pause: () async {},
      backward: (_) async {},
      forward: (_) async {},
      stepBackward: () async {},
      stepForward: () async {},
      seek: (_) async {},
    );
    await tester.pumpWidget(providerScope(
      Provider<MediaPlayer>.value(
        value: player,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MoreMenuButton(
              showControl: () {},
              showControlForHover: (f) async => await f,
            ),
          ),
        ),
      ),
    ));
    // Deferred ARB loading resolves asynchronously.
    await tester.pumpAndSettle();
  }

  testWidgets('more menu opens and lists the phone playback tools',
      (tester) async {
    await pumpButton(tester);

    await tester.tap(find.byKey(moreMenuKeyNotifier.value!));
    await tester.pumpAndSettle();

    expect(find.text('逐帧工具'), findsOneWidget);
    expect(find.text('截存当前帧'), findsOneWidget);
  });

  testWidgets('tapping the frame-tools entry toggles the float panel flag',
      (tester) async {
    await pumpButton(tester);

    await tester.tap(find.byKey(moreMenuKeyNotifier.value!));
    await tester.pumpAndSettle();
    expect(usePlaybackToolsStore().state.frameToolsVisible, isFalse);

    await tester.tap(find.text('逐帧工具'));
    await tester.pumpAndSettle();

    expect(usePlaybackToolsStore().state.frameToolsVisible, isTrue);
  });
}
