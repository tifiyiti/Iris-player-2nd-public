import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/playback_tools/store/playback_tools_store.dart';
import 'package:iris/features/playback_tools/view/frame_tools_float_panel.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/player.dart';
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

void main() {
  final steps = <int>[];
  late MediaPlayer player;

  setUp(() {
    steps.clear();
    usePlaybackToolsStore().hideFrameTools();
    player = MediaPlayer(
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
      stepBackward: () async => steps.add(-1),
      stepForward: () async => steps.add(1),
      seek: (_) async {},
    );
  });

  // NOTE (probe-verified in gesture_guide_overlay_test): flutter_zustand's
  // select()→rebuild chain does not deliver under the widget-test FakeAsync
  // zone, so the store must be mutated BEFORE pumping and the panel must
  // REMOUNT via a fresh key to observe the new state.
  Future<void> pumpPanel(
    WidgetTester tester, {
    bool visible = true,
    bool withLocalizations = true,
  }) async {
    visible
        ? usePlaybackToolsStore().showFrameTools()
        : usePlaybackToolsStore().hideFrameTools();
    final Widget app = withLocalizations
        ? MaterialApp(
            // Deferred ARB loading only resolves via pumpAndSettle (probe-
            // verified in gesture_guide_overlay_test), so the delegates are
            // mounted ONLY for tests that render localized dialog content.
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Stack(children: [FrameToolsFloatPanel(key: UniqueKey())]),
          )
        : MaterialApp(
            home: Stack(children: [FrameToolsFloatPanel(key: UniqueKey())]),
          );
    await tester.pumpWidget(providerScope(
      Provider<MediaPlayer>.value(value: player, child: app),
    ));
    if (withLocalizations) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Finder panelCard() => find.byKey(const ValueKey('frame_tools_panel'));

  testWidgets('hidden state renders nothing', (tester) async {
    await pumpPanel(tester, visible: false);
    expect(panelCard(), findsNothing);
  });

  testWidgets('visible state renders step/shutter/close controls',
      (tester) async {
    await pumpPanel(tester);
    expect(panelCard(), findsOneWidget);
    expect(find.byTooltip('Previous frame'), findsOneWidget);
    expect(find.byTooltip('Next frame'), findsOneWidget);
    expect(find.byTooltip('Capture current frame'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
  });

  testWidgets('frame buttons invoke the matching player step',
      (tester) async {
    await pumpPanel(tester);

    await tester.tap(find.byTooltip('Next frame'));
    await tester.tap(find.byTooltip('Previous frame'));
    await tester.pump();
    expect(steps, [1, -1]);
  });

  testWidgets('shutter on non-mediaKit backend explains the unsupported backend',
      (tester) async {
    await pumpPanel(tester, withLocalizations: true);

    await tester.tap(find.byTooltip('Capture current frame'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Current backend cannot screenshot'), findsOneWidget);
    expect(find.textContaining('fvp'), findsOneWidget);
  });

  testWidgets('close flips the store flag off', (tester) async {
    await pumpPanel(tester);
    expect(usePlaybackToolsStore().state.frameToolsVisible, isTrue);

    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    expect(usePlaybackToolsStore().state.frameToolsVisible, isFalse);

    // Re-mounting now renders nothing (FakeAsync-safe verification).
    await pumpPanel(tester, visible: false);
    expect(panelCard(), findsNothing);
  });

  testWidgets('dragging the card moves it within the stack', (tester) async {
    await pumpPanel(tester);

    final before = tester.widget<Positioned>(
      find.ancestor(of: panelCard(), matching: find.byType(Positioned)).first,
    );

    await tester.drag(panelCard(), const Offset(160, 120));
    await tester.pump();

    final after = tester.widget<Positioned>(
      find.ancestor(of: panelCard(), matching: find.byType(Positioned)).first,
    );
    expect(after.left! - before.left!, greaterThan(100));
    expect(after.top! - before.top!, greaterThan(70));
  });

  testWidgets(
      'REGRESSION: the mounted card stays compact (no near-fullscreen stretch)',
      (tester) async {
    // Mirrors player.dart's mount AFTER the fix: the panel is a direct Stack
    // child. The old Positioned.fill wrapper double-wrote StackParentData
    // (right/bottom stayed 0) and stretched the Material box from (16,120)
    // to (W,H) — the reported full-white overlay.
    usePlaybackToolsStore().showFrameTools();

    await tester.pumpWidget(providerScope(
      Provider<MediaPlayer>.value(
        value: player,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Stack(children: [FrameToolsFloatPanel(key: UniqueKey())]),
        ),
      ),
    ));
    await tester.pumpAndSettle(); // deferred l10n + post-frame placement

    final size = tester.getSize(panelCard());
    final stackWidth = tester.getSize(find.byType(Stack)).width;
    expect(size.width, lessThan(stackWidth / 2),
        reason: 'card must not stretch across the screen');
  });

  testWidgets('first appearance is horizontally centered in its stack',
      (tester) async {
    usePlaybackToolsStore().showFrameTools();

    await tester.pumpWidget(providerScope(
      Provider<MediaPlayer>.value(
        value: player,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Stack(children: [FrameToolsFloatPanel(key: UniqueKey())]),
        ),
      ),
    ));
    await tester.pumpAndSettle(); // deferred l10n + post-frame placement

    final stackWidth = tester.getSize(find.byType(Stack)).width;
    final center = tester.getCenter(panelCard());
    expect(center.dx, closeTo(stackWidth / 2, 1));
  });
}
