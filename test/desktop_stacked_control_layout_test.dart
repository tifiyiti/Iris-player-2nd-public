import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/features/windows/desktop_control_bar/view/desktop_stacked_control_layout.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/control_bar/control_bar_layout/control_bar_controls.dart';
import 'package:iris/pages/player/control_bar/control_bar_layout/desktop_control_layout.dart';
import 'package:iris/pages/player/control_bar/control_bar_slider.dart';
import 'package:provider/provider.dart';
import 'package:zustand/zustand.dart';

// PotPlayer-style three-row desktop bar: time labels above a full-width
// seek bar above the button row. The button row must keep the EXACT
// left/right arrangement of the classic one-line DesktopControlLayout —
// only the slider and the time display moved.

const double _canvasWidth = 1280;
const double _canvasHeight = 220;

MediaPlayer _player() {
  return MediaPlayer(
    isInitializing: false,
    isPlaying: false,
    externalSubtitles: const [],
    position: const Duration(seconds: 12),
    duration: const Duration(hours: 1),
    buffer: Duration.zero,
    width: 16,
    height: 9,
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

ControlBarControls _controls() {
  return ControlBarControls(
    showControl: () {},
    showControlForHover: (_) async {},
    color: Colors.white,
    overlayColor: null,
    file: const FileItem(name: 'a.mp4', uri: 'file:///a.mp4'),
    circleScale: 0.5,
  );
}

/// StoreScope-equivalent that does NOT dispose the global StoreLocator on
/// unmount. [StoreScope] tears it down fire-and-forget, which races the next
/// test's first `set()` ("Cannot add new events after calling close") because
/// the stores created in `setUp` live in that same global locator.
Widget _providerScope(Widget child) => InheritedProvider<StoreLocator>.value(
      value: StoreLocator(),
      startListening: (InheritedContext<StoreLocator?> e, StoreLocator value) {
        final sub = value.changes.listen((_) => e.markNeedsNotifyDependents());
        return sub.cancel;
      },
      lazy: false,
      child: child,
    );

Widget _harness(Widget child) {
  return _providerScope(
    Provider<MediaPlayer>.value(
      value: _player(),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: _canvasWidth,
              height: _canvasHeight,
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

/// The default test surface (800x600) would clamp the canvas; give it a
/// desktop-sized window so the layouts get their real width budget.
void _setDesktopSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

List<IconData> _iconSequence(WidgetTester tester) =>
    tester
        .widgetList<IconButton>(find.byType(IconButton))
        .map((b) => b.icon is Icon ? (b.icon as Icon).icon : null)
        .whereType<IconData>()
        .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  // StoreScope.onReady touches DbModule-backed stores; bootstrap a memory DB.
  setUpAll(() async {
    await DbModule.init(AppDatabase(NativeDatabase.memory()));
  });

  setUp(() {
    // The 副音 quick bar renders inside this layout; these tests cover the
    // control bar's OWN button row, so keep the quick bar out of the way.
    final bg = useBackgroundPlaybackStore();
    bg.set(bg.state.copyWith(enabled: false, quickBarEnabled: false));
  });

  testWidgets('stacks time labels above the seek bar above the buttons',
      (tester) async {
    _setDesktopSurface(tester);
    await tester.pumpWidget(
      _harness(DesktopStackedControlLayout(controls: _controls())),
    );
    await tester.pumpAndSettle();

    final layoutBounds = tester.getRect(find.byType(DesktopStackedControlLayout));

    // Row 1 — combined "position / duration" together on the LEFT.
    final combinedRect = tester.getRect(find.text('00:12 / 60:00'));
    expect(combinedRect.left, moreOrLessEquals(layoutBounds.left, epsilon: 1),
        reason: 'combined position/duration label hugs the left edge');
    // No separate right-aligned duration — both together left.
    expect(find.text('00:12'), findsNothing);
    expect(find.text('60:00'), findsNothing);

    // Row 2 — seek bar BELOW combined label.
    final sliderRect = tester.getRect(
      find.descendant(
        of: find.byType(ControlBarSlider),
        matching: find.byType(Slider),
      ),
    );
    expect(sliderRect.top, greaterThanOrEqualTo(combinedRect.bottom));

    // Row 3 — buttons below the seek bar.
    for (final btn in find.byType(IconButton).evaluate()) {
      expect(tester.getRect(find.byWidget(btn.widget)).top,
          greaterThanOrEqualTo(sliderRect.bottom),
          reason: 'every button sits below the seek bar');
    }
  });

  testWidgets('seek bar spans nearly the full canvas width without inline '
      'time texts', (tester) async {
    _setDesktopSurface(tester);
    await tester.pumpWidget(
      _harness(DesktopStackedControlLayout(controls: _controls())),
    );
    await tester.pumpAndSettle();

    final sliderRect = tester.getRect(
      find.descendant(
        of: find.byType(ControlBarSlider),
        matching: find.byType(Slider),
      ),
    );
    // ControlBarSlider carries 12px side padding; the track must claim
    // everything else (the point of the stacked mode is a longer axis).
    expect(sliderRect.width, greaterThan(_canvasWidth - 40));

    // The inline position/duration texts must NOT render inside the
    // slider row — they moved to their own line above it.
    expect(
      find.descendant(
        of: find.byType(ControlBarSlider),
        matching: find.text('00:12'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(ControlBarSlider),
        matching: find.text('60:00'),
      ),
      findsNothing,
    );
  });

  testWidgets('button arrangement matches the one-line desktop layout '
      'exactly', (tester) async {
    _setDesktopSurface(tester);
    await tester.pumpWidget(_harness(DesktopControlLayout(controls: _controls())));
    await tester.pumpAndSettle();
    final oneLineIcons = _iconSequence(tester);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      _harness(DesktopStackedControlLayout(controls: _controls())),
    );
    await tester.pumpAndSettle();
    final stackedIcons = _iconSequence(tester);

    expect(stackedIcons, oneLineIcons,
        reason: 'same buttons in the same order — only the slider and '
            'time display moved');
  });

  testWidgets('button row keeps left group flush-left and right group '
      'flush-right', (tester) async {
    _setDesktopSurface(tester);
    await tester.pumpWidget(
      _harness(DesktopStackedControlLayout(controls: _controls())),
    );
    await tester.pumpAndSettle();

    final layoutBounds = tester.getRect(find.byType(DesktopStackedControlLayout));
    final rects =
        find.byType(IconButton).evaluate().map((e) => tester.getRect(find.byWidget(e.widget))).toList()
          ..sort((a, b) => a.left.compareTo(b.left));

    expect(rects, isNotEmpty);
    expect(rects.first.left, moreOrLessEquals(layoutBounds.left, epsilon: 2),
        reason: 'play/pause group stays flush-left');
    expect(rects.last.right, moreOrLessEquals(layoutBounds.right, epsilon: 2),
        reason: 'more-menu stays flush-right');

    // All buttons share ONE baseline (a single row).
    final ys = rects.map((r) => r.center.dy).toSet();
    expect(ys.length, 1, reason: 'buttons form a single row');
  });

  /// Regression guard: the classic bar packs the transport group flush-left and
  /// the secondary group flush-right with ONE large gap between them. A flat
  /// `Wrap(spaceBetween)` over every button also puts the first/last button at
  /// the edges — so the flush-left/flush-right assertions above stay green — but
  /// it spreads ALL buttons evenly and destroys the grouping. Only the size of
  /// the largest gap can tell the two apart.
  List<Rect> sortedButtonRects(WidgetTester tester) => find
      .byType(IconButton)
      .evaluate()
      .map((e) => tester.getRect(find.byWidget(e.widget)))
      .toList()
    ..sort((a, b) => a.left.compareTo(b.left));

  void expectGroupedWithOneBigGap(List<Rect> rects) {
    expect(rects.length, greaterThan(4), reason: 'need a multi-button row');
    final gaps = <double>[
      for (int i = 1; i < rects.length; i++) rects[i].left - rects[i - 1].right,
    ];
    final double maxGap = gaps.reduce((a, b) => a > b ? a : b);
    final double minGap = gaps.reduce((a, b) => a < b ? a : b);
    // Inside a group the buttons sit edge-to-edge (a `Row`), so the smallest
    // gap stays ~0. A flat `Wrap(spaceBetween)` over every button instead
    // injects slack between EVERY adjacent pair, which is what visually pulls
    // the left group inward and the right group outward. Exactly ONE large gap
    // may remain: the one between the two groups.
    expect(
      minGap,
      lessThan(8),
      reason: 'buttons inside a group must be packed edge-to-edge; a flat '
          'spaceBetween spread injects slack between every pair',
    );
    expect(
      maxGap,
      greaterThan(100),
      reason: 'the transport and secondary groups must stay separated by one '
          'large gap',
    );
  }

  testWidgets('stacked: left group and right group stay contiguous',
      (tester) async {
    _setDesktopSurface(tester);
    await tester.pumpWidget(
      _harness(DesktopStackedControlLayout(controls: _controls())),
    );
    await tester.pumpAndSettle();

    expectGroupedWithOneBigGap(sortedButtonRects(tester));
  });

  testWidgets('single-line: left group and right group stay contiguous',
      (tester) async {
    _setDesktopSurface(tester);
    await tester.pumpWidget(_harness(DesktopControlLayout(controls: _controls())));
    await tester.pumpAndSettle();

    expectGroupedWithOneBigGap(sortedButtonRects(tester));
  });
}
