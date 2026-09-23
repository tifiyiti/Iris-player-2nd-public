import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/view/segment_edit_button_bar.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/player.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:provider/provider.dart';
import 'package:zustand/zustand.dart';

/// The align editor's bottom bar: transport + seek step + volume split +
/// snap toggle + A/B + P + silence toggle + save / exit, and (side type)
/// the ring swap.
///
/// Must fit a 360px-wide phone without overflow (it `Wrap`s onto extra lines)
/// and every action must fire its callback.
///
/// The A/B button resolves its single endpoint from the LIVE foreground
/// position, so the harness provides a [MediaPlayer] whose `position` /
/// `duration` the test drives.
MediaPlayer _fakePlayer({
  int positionMs = 0,
  int durationMs = 100000,
}) {
  return MediaPlayer(
    isInitializing: false,
    isPlaying: false,
    externalSubtitles: const [],
    position: Duration(milliseconds: positionMs),
    duration: Duration(milliseconds: durationMs),
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
}

Widget _harness({
  bool snapOn = false,
  required VoidCallback onToggleSnap,
  VoidCallback? onSwapRings,
  VoidCallback? onSave,
  VoidCallback? onExit,
  VoidCallback? onPlayPause,
  VoidCallback? onToggleSilence,
  bool silenceOn = false,
  bool isPlaying = false,
  bool isDisplayingBg = false,
  VoidCallback? onToggleDisplay,
  int? abCenterMs = 40000,
  int fgPosMs = 0,
  VoidCallback? onMoveA,
  VoidCallback? onMoveB,
  bool canMoveP = true,
  VoidCallback? onMoveP,
}) {
  return Provider<MediaPlayer>.value(
    value: _fakePlayer(positionMs: fgPosMs),
    child: InheritedProvider<StoreLocator>.value(
      value: StoreLocator(),
      startListening: (InheritedContext<StoreLocator?> e, StoreLocator value) {
        final sub = value.changes.listen((_) => e.markNeedsNotifyDependents());
        return sub.cancel;
      },
      lazy: false,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: SegmentEditButtonBar(
                isPlaying: isPlaying,
                onPlayPause: onPlayPause ?? () {},
                onBackward: () {},
                onForward: () {},
                snapOn: snapOn,
                onToggleSnap: onToggleSnap,
                onSave: onSave ?? () {},
                onExit: onExit ?? () {},
                onSwapRings: onSwapRings,
                isDisplayingBg: isDisplayingBg,
                onToggleDisplay: onToggleDisplay ?? () {},
                abCenterMs: abCenterMs,
                onMoveA: onMoveA ?? () {},
                onMoveB: onMoveB ?? () {},
                canMoveP: canMoveP,
                onMoveP: onMoveP ?? () {},
                silenceOn: silenceOn,
                onToggleSilence: onToggleSilence ?? () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Whether the move-to-current letter button under [key] is enabled (its
/// [TextButton.onPressed] is non-null).
bool _moveEnabled(WidgetTester tester, String key) {
  final btn = tester.widget<TextButton>(
    find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byType(TextButton),
    ),
  );
  return btn.onPressed != null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ch = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(ch, (call) async => null);

  setUp(() {
    useAppStore().set(useAppStore().state.copyWith(
          useMetadataSettings: true,
          useLegacyStoragePersistence: false,
        ));
  });

  testWidgets('fits a 360px phone without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness(
      onToggleSnap: () {},
      onSwapRings: () {},
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('segment_edit_button_bar')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('save / exit / play-pause / silence toggle fire their callbacks',
      (tester) async {
    var saved = 0, exited = 0, played = 0, silenced = 0;
    await tester.pumpWidget(_harness(
      onToggleSnap: () {},
      onSave: () => saved++,
      onExit: () => exited++,
      onPlayPause: () => played++,
      onToggleSilence: () => silenced++,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('segment_edit_save')));
    await tester.tap(find.byKey(const ValueKey('segment_edit_save_silent')));
    await tester.tap(find.byKey(const ValueKey('segment_edit_exit')));
    await tester.tap(find.byKey(const ValueKey('segment_edit_play_pause')));
    await tester.pump();

    expect(saved, 1);
    expect(silenced, 1);
    expect(exited, 1);
    expect(played, 1);
    // The volume button is always present (it opens a popover, not a sheet).
    expect(find.byKey(const ValueKey('segment_edit_volume')), findsOneWidget);
  });

  testWidgets('the ring-swap button is side-type only', (tester) async {
    await tester.pumpWidget(_harness(
      onToggleSnap: () {},
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('segment_edit_swap_rings')), findsNothing);

    await tester.pumpWidget(_harness(
      onToggleSnap: () {},
      onSwapRings: () {},
    ));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('segment_edit_swap_rings')), findsOneWidget);
  });

  testWidgets('A and B each have their own button; P is hidden',
      (tester) async {
    var a = 0, b = 0;
    await tester.pumpWidget(_harness(
      onToggleSnap: () {},
      abCenterMs: 40000,
      fgPosMs: 10000,
      onMoveA: () => a++,
      onMoveB: () => b++,
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('segment_edit_move_a')), findsOneWidget);
    expect(find.byKey(const ValueKey('segment_edit_move_b')), findsOneWidget);
    // P move-to-current is disabled (kEnablePMoveButton) for now.
    expect(find.byKey(const ValueKey('segment_edit_move_p')), findsNothing);

    // Playhead left of the 40s centre → A is active.
    await tester.tap(find.byKey(const ValueKey('segment_edit_move_a')));
    await tester.pump();
    expect(a, 1);
    expect(b, 0);
  });

  testWidgets('the illegal endpoint\'s button is greyed', (tester) async {
    await tester.pumpWidget(_harness(
      onToggleSnap: () {},
      abCenterMs: 40000,
      fgPosMs: 35000,
    ));
    await tester.pumpAndSettle();
    expect(_moveEnabled(tester, 'segment_edit_move_a'), isTrue);
    expect(_moveEnabled(tester, 'segment_edit_move_b'), isFalse);

    await tester.pumpWidget(_harness(
      onToggleSnap: () {},
      abCenterMs: 40000,
      fgPosMs: 45000,
    ));
    await tester.pumpAndSettle();
    expect(_moveEnabled(tester, 'segment_edit_move_a'), isFalse);
    expect(_moveEnabled(tester, 'segment_edit_move_b'), isTrue);

    // Exactly at the centre neither endpoint may move.
    await tester.pumpWidget(_harness(
      onToggleSnap: () {},
      abCenterMs: 40000,
      fgPosMs: 40000,
    ));
    await tester.pumpAndSettle();
    expect(_moveEnabled(tester, 'segment_edit_move_a'), isFalse);
    expect(_moveEnabled(tester, 'segment_edit_move_b'), isFalse);
  });

  testWidgets('a greyed endpoint button does not fire', (tester) async {
    var a = 0, b = 0;
    await tester.pumpWidget(_harness(
      onToggleSnap: () {},
      abCenterMs: 40000,
      fgPosMs: 45000,
      onMoveA: () => a++,
      onMoveB: () => b++,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('segment_edit_move_a')));
    await tester.pump();
    expect(a, 0, reason: 'A is illegal right of the centre');

    await tester.tap(find.byKey(const ValueKey('segment_edit_move_b')));
    await tester.pump();
    expect(b, 1);
  });

  testWidgets('the display-target button reports its state and toggles',
      (tester) async {
    var toggled = 0;
    await tester.pumpWidget(_harness(
      onToggleSnap: () {},
      isDisplayingBg: true,
      onToggleDisplay: () => toggled++,
    ));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.smart_display_rounded), findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('segment_edit_display_target')));
    await tester.pump();
    expect(toggled, 1);
  });

  testWidgets('never offers a bg switcher (alignment-only edit bar)',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness(onToggleSnap: () {}));
    await tester.pumpAndSettle();

    // The APB panel exists only to align and save/discard the current pair: no
    // prev/next/name/queue entry may swap the 副音 out from under the span.
    expect(find.byKey(const ValueKey('segment_edit_bg_prev')), findsNothing);
    expect(find.byKey(const ValueKey('segment_edit_bg_next')), findsNothing);
    expect(find.byKey(const ValueKey('segment_edit_bg_name')), findsNothing);
    expect(find.byKey(const ValueKey('segment_edit_bg_browse')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the snap toggle fires and reflects its active state',
      (tester) async {
    var toggled = 0;
    await tester.pumpWidget(_harness(
      snapOn: false,
      onToggleSnap: () => toggled++,
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('segment_snap_button')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('segment_snap_button')));
    await tester.pump();
    expect(toggled, 1);

    await tester.pumpWidget(_harness(
      snapOn: true,
      onToggleSnap: () {},
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('segment_snap_button')), findsOneWidget);
  });
}
