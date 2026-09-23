import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/overlays/gesture_overlay.dart';
import 'package:provider/provider.dart';
import 'package:zustand/zustand.dart';

Widget _providerScope(Widget child) {
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

MediaPlayer _fakePlayer() => MediaPlayer(
      isInitializing: false,
      isPlaying: true,
      externalSubtitles: const [],
      position: Duration.zero,
      duration: const Duration(minutes: 10),
      buffer: Duration.zero,
      width: 1280,
      height: 720,
      saveProgress: () async {},
      play: () async {},
      pause: () async {},
      backward: (_) async {},
      forward: (_) async {},
      stepBackward: () async {},
      stepForward: () async {},
      seek: (_) async {},
    );

Widget _harness({required MediaPlayer player}) {
  return _providerScope(
    Provider<MediaPlayer>.value(
      value: player,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox.expand(
            child: GestureOverlay(
              showControl: () {},
              hideControl: () {},
              showProgress: () {},
              showControlForHover: (cb) async => cb,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('GestureOverlay builds without error (desktop)', (tester) async {
    final player = _fakePlayer();
    await tester.pumpWidget(_harness(player: player));
    await tester.pumpAndSettle();
    expect(find.byType(GestureOverlay), findsOneWidget);
  });

  testWidgets('right-click opens PotPlayer-style menu', (tester) async {
    final player = _fakePlayer();
    await tester.pumpWidget(_harness(player: player));
    await tester.pumpAndSettle();

    final center = tester.getCenter(find.byType(GestureOverlay));

    // Send secondary (right) click at center.
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await gesture.down(center);
    await gesture.up();
    await tester.pumpAndSettle();

    // Top-level entries should now be in the overlay.
    // MenuAnchor renders menuChildren in an OverlayPortal.
    expect(find.text('Open'), findsWidgets);
    expect(find.text('Playback'), findsOneWidget);
    expect(find.text('Video'), findsOneWidget);
    expect(find.text('Audio'), findsOneWidget);
    expect(find.text('Subtitle'), findsOneWidget);
    expect(find.text('Window'), findsOneWidget);
  });

  testWidgets('menu contains nested Speed and A-B loop under Playback', (tester) async {
    final player = _fakePlayer();
    await tester.pumpWidget(_harness(player: player));
    await tester.pumpAndSettle();

    final center = tester.getCenter(find.byType(GestureOverlay));
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await gesture.down(center);
    await gesture.up();
    await tester.pumpAndSettle();

    // Playback submenu should be visible; opening it reveals Speed/A-B.
    // Tap Playback to expand its submenu.
    await tester.tap(find.text('Playback'));
    await tester.pumpAndSettle();

    expect(find.text('Speed'), findsOneWidget);
    expect(find.text('A-B loop'), findsOneWidget);
  });
}
