import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/engine/background_playback_engine.dart';
import 'package:iris/features/background_playback/model/enum/bg_align_default.dart';
import 'package:iris/features/background_playback/model/enum/bg_align_mode.dart';
import 'package:iris/features/background_playback/model/enum/bg_exhausted_action.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/features/background_playback/view/bg_align_dialog.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/player.dart';
import 'package:iris/models/store/app_state.dart' show PlayerBackend;
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/warning_dialogs.dart';
import 'package:provider/provider.dart';
import 'package:zustand/zustand.dart';

/// The shared 副音 alignment editor: a scope switch (update-now vs
/// save-as-default) over three shared anchor modes, with a decoupled percent
/// slider that never seeks by itself.
MediaPlayer _fakePlayer() => MediaPlayer(
      isInitializing: false,
      isPlaying: true,
      externalSubtitles: const [],
      position: const Duration(seconds: 40),
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

Widget _harness({
  required MediaPlayer player,
  required BackgroundPlaybackEngine engine,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return InheritedProvider<StoreLocator>.value(
    value: StoreLocator(),
    startListening: (InheritedContext<StoreLocator?> e, StoreLocator value) {
      final sub = value.changes.listen((_) => e.markNeedsNotifyDependents());
      return sub.cancel;
    },
    lazy: false,
    child: Provider<MediaPlayer>.value(
      value: player,
      child: ChangeNotifierProvider<BackgroundPlaybackEngine>.value(
        value: engine,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: textScaler),
              child: const Scaffold(
                body: SingleChildScrollView(child: BgAlignContent()),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  late BackgroundPlaybackEngine engine;

  setUp(() async {
    engine = BackgroundPlaybackEngine(
      backend: PlayerBackend.mediaKit,
      attachNative: false,
    );
    final bg = useBackgroundPlaybackStore();
    await bg.initialized;
    // Normal active state: 副音 enabled AND the user gate open (the update
    // scope only exists while 副音 is actually mixing).
    bg.set(bg.state.copyWith(enabled: true, gateOpen: true));
  });

  tearDown(() async {
    engine.dispose();
    // Drop the app-wide singletons so every test builds its stores inside its
    // own fake-async zone. A shared AppStore created in an earlier test's zone
    // can never complete `initialized` here and loses change propagation.
    await StoreLocator().delete(BackgroundPlaybackStore);
    await StoreLocator().delete(AppStore);
  });

  testWidgets('renders without overflow on a 360x640 phone at large font',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness(
      player: _fakePlayer(),
      engine: engine,
      textScaler: const TextScaler.linear(1.3),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(BgAlignContent), findsOneWidget);
  });

  testWidgets('shows one scope switch over the three shared modes',
      (tester) async {
    await tester.pumpWidget(_harness(player: _fakePlayer(), engine: engine));
    await tester.pumpAndSettle();

    // The scope switch is a SegmentedButton over a private enum, so match
    // by subtype instead of an exact generic instantiation.
    expect(
      find.byWidgetPredicate((w) => w is SegmentedButton),
      findsOneWidget,
    );
    expect(find.text('Update alignment'), findsOneWidget);
    expect(find.text('Default alignment'), findsOneWidget);
    // The at-position label exists exactly once (shared by both scopes).
    expect(
      find.text(
          'Sub Audio starts at its 00:00 at the video\'s current position'),
      findsOneWidget,
    );
    // The default hint lives only in the 默认对齐 scope.
    expect(find.textContaining('Current default:'), findsNothing);
    await tester.tap(find.text('Default alignment'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Current default:'), findsOneWidget);
  });

  testWidgets('gate shut hides the update scope; taps only save the default',
      (tester) async {
    final bg = useBackgroundPlaybackStore();
    bg.set(bg.state.copyWith(gateOpen: false));
    expect(bg.state.alignMode, BgAlignMode.fromFgHead);
    expect(bg.state.alignDefault, BgAlignDefault.fgHead);

    await tester.pumpWidget(_harness(player: _fakePlayer(), engine: engine));
    await tester.pumpAndSettle();

    // No live-update surface, and no scope switch to reach it.
    expect(find.byWidgetPredicate((w) => w is SegmentedButton), findsNothing);
    expect(find.text('Update alignment'), findsNothing);
    // The "applies next alignment" framing is always shown while shut.
    expect(find.textContaining('Current default:'), findsOneWidget);

    final finder = find.text(
        'Sub Audio starts at its 00:00 at the video\'s current position');
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();

    expect(bg.state.alignDefault, BgAlignDefault.fgPosition);
    expect(bg.state.alignMode, BgAlignMode.fromFgHead,
        reason: 'the (stopped) running pair is never touched while the gate is '
            'shut');
  });

  testWidgets('update scope taps the mode without touching the default',
      (tester) async {
    final bg = useBackgroundPlaybackStore();
    expect(bg.state.alignMode, BgAlignMode.fromFgHead);
    expect(bg.state.alignDefault, BgAlignDefault.fgHead);

    await tester.pumpWidget(_harness(player: _fakePlayer(), engine: engine));
    await tester.pumpAndSettle();

    final finder = find.text(
        'Sub Audio starts at its 00:00 at the video\'s current position');
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();

    expect(bg.state.alignMode, BgAlignMode.atFgPosition);
    expect(bg.state.alignDefault, BgAlignDefault.fgHead);
  });

  testWidgets('default scope saves without seeking the running pair',
      (tester) async {
    final bg = useBackgroundPlaybackStore();
    expect(bg.state.alignMode, BgAlignMode.fromFgHead);

    await tester.pumpWidget(_harness(player: _fakePlayer(), engine: engine));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Default alignment'));
    await tester.pumpAndSettle();

    final finder = find.text(
        'Sub Audio starts at its 00:00 at the video\'s current position');
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();

    expect(bg.state.alignDefault, BgAlignDefault.fgPosition);
    // The running pair is untouched: no mode change, no seek.
    expect(bg.state.alignMode, BgAlignMode.fromFgHead);
    // The hint reflects the new default so the change is visible at a glance.
    expect(find.textContaining('Current default:'), findsOneWidget);
  });

  testWidgets('the percent slider edits the share without seeking',
      (tester) async {
    final bg = useBackgroundPlaybackStore();
    final before = bg.state.alignPercent;

    await tester.pumpWidget(_harness(player: _fakePlayer(), engine: engine));
    await tester.pumpAndSettle();

    final slider = find.byKey(const ValueKey('bg_align_percent_slider'));
    expect(slider, findsOneWidget);
    await tester.drag(slider, const Offset(60, 0));
    await tester.pumpAndSettle();

    expect(bg.state.alignPercent, isNot(equals(before)));
    expect(bg.state.alignMode, BgAlignMode.fromFgHead);
  });

  testWidgets('alignment section sits above other settings', (tester) async {
    await tester.pumpWidget(_harness(player: _fakePlayer(), engine: engine));
    await tester.pumpAndSettle();

    final alignTitle = find.text('Alignment');
    final otherTitle = find.text('Other');
    expect(alignTitle, findsOneWidget);
    expect(otherTitle, findsOneWidget);
    // The slider (alignment) renders above the 其他设置 boundary.
    final slider = find.byKey(const ValueKey('bg_align_percent_slider'));
    expect(slider, findsOneWidget);
    expect(
      tester.getTopLeft(alignTitle).dy,
      lessThan(tester.getTopLeft(slider).dy),
    );
    expect(
      tester.getTopLeft(slider).dy,
      lessThan(tester.getTopLeft(otherTitle).dy),
    );
  });

  testWidgets('the default hint hides forever and comes back on reset',
      (tester) async {
    // NOTE: never `await useAppStore().initialized` in a widget test — the
    // store is a process-wide singleton created inside whichever test's
    // fake-async zone ran first, so its completer can never resolve here.
    // `set` is synchronous, which is all the UI assertions need.
    final app = useAppStore();

    await tester.pumpWidget(_harness(player: _fakePlayer(), engine: engine));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Default alignment'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Current default:'), findsOneWidget);

    final hide =
        find.byKey(const ValueKey('bg_align_default_hint_hide'));
    await tester.ensureVisible(hide);
    await tester.tap(hide);
    await tester.pumpAndSettle();

    expect(app.state.suppressedWarnings, contains(kWarningBgAlignDefaultHint));
    expect(find.textContaining('Current default:'), findsNothing);

    // 取消永关: resetting brings the hint back.
    await app.resetWarning(kWarningBgAlignDefaultHint);
    await tester.pumpAndSettle();
    expect(find.textContaining('Current default:'), findsOneWidget);
  });

  testWidgets('the percent caption hides forever and comes back on reset',
      (tester) async {
    final app = useAppStore();

    await tester.pumpWidget(_harness(player: _fakePlayer(), engine: engine));
    await tester.pumpAndSettle();

    expect(find.textContaining('Tune the share'), findsOneWidget);
    final hide =
        find.byKey(const ValueKey('bg_align_percent_hint_hide'));
    await tester.ensureVisible(hide);
    await tester.tap(hide);
    await tester.pumpAndSettle();

    expect(find.textContaining('Tune the share'), findsNothing);
    expect(app.state.suppressedWarnings, contains(kWarningBgAlignPercentHint));

    await app.resetWarning(kWarningBgAlignPercentHint);
    await tester.pumpAndSettle();
    expect(find.textContaining('Tune the share'), findsOneWidget);
  });

  testWidgets('picking stopRestoreFg records the exhausted action',
      (tester) async {
    final bg = useBackgroundPlaybackStore();
    await tester.pumpWidget(_harness(player: _fakePlayer(), engine: engine));
    await tester.pumpAndSettle();

    final finder =
        find.text('Pause Sub Audio and restore the video\'s own audio');
    await tester.scrollUntilVisible(finder, 120,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(finder);
    await tester.pumpAndSettle();

    expect(bg.state.bgExhaustedAction, BgExhaustedAction.stopRestoreFg);
  });
}
