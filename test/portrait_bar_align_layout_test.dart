import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/features/control_group/model/enum/player_control_group.dart';
import 'package:iris/features/control_group/store/use_control_group_store.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/pages/player/control_bar/control_bar_layout/control_bar_controls.dart';
import 'package:iris/pages/player/control_bar/control_bar_layout/mobile_control_layout.dart';
import 'package:iris/pages/player/control_bar/control_bar_widgets/repeat_button.dart';
import 'package:iris/pages/player/control_bar/control_bar_widgets/shuffle_button.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/widgets/dialogs/show_portrait_bar_align_dialog.dart';
import 'package:provider/provider.dart';

/// Phone-PORTRAIT bottom bar: the two groups carry INDEPENDENT alignment.
/// Playback rows map to `MainAxisAlignment`; the shrink-wrapped 副音 block is
/// positioned by an outer `Align` (a bare Column child would always centre).
MediaPlayer _player() => MediaPlayer(
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

ControlBarControls _controls() => ControlBarControls(
      showControl: () {},
      showControlForHover: (_) async {},
      color: Colors.white,
      overlayColor: null,
      file: const FileItem(name: 'a.mp4', uri: 'file:///a.mp4'),
      circleScale: 0.5,
    );

Widget _harness(Widget child) => StoreScope(
      child: Provider<MediaPlayer>.value(
        value: _player(),
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: Center(child: child)),
        ),
      ),
    );

/// Fixed 400px bar (phone-portrait width) so edge offsets are deterministic.
Widget _bar() =>
    SizedBox(width: 400, child: MobileControlLayout(controls: _controls()));

void _setSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  setUpAll(() async {
    await DbModule.init(AppDatabase(NativeDatabase.memory()));
  });

  setUp(() {
    final app = useAppStore();
    app.set(app.state.copyWith(
      useMetadataSettings: true,
      useLegacyStoragePersistence: false,
      portraitPlaybackAlign: PortraitBarAlign.center,
      portraitSubAudioAlign: PortraitBarAlign.center,
    ));
    useControlGroupStore().set(
        useControlGroupStore().state.copyWith(group: PlayerControlGroup.playback));
  });

  testWidgets('playback rows: left packs both rows to the left edge',
      (tester) async {
    _setSurface(tester);
    useAppStore().set(useAppStore()
        .state
        .copyWith(portraitPlaybackAlign: PortraitBarAlign.left));
    await tester.pumpWidget(_harness(_bar()));
    await tester.pumpAndSettle();

    final double left = tester.getTopLeft(find.byType(ShuffleButton)).dx;
    expect(left, lessThanOrEqualTo(1.0),
        reason: 'left: shuffle starts at the bar edge');
  });

  testWidgets('playback rows: right packs both rows to the right edge',
      (tester) async {
    _setSurface(tester);
    useAppStore().set(useAppStore()
        .state
        .copyWith(portraitPlaybackAlign: PortraitBarAlign.right));
    await tester.pumpWidget(_harness(_bar()));
    await tester.pumpAndSettle();

    final double right = tester.getTopRight(find.byType(RepeatButton)).dx;
    expect(right, greaterThanOrEqualTo(399.0),
        reason: 'right: repeat ends at the bar edge');
  });

  testWidgets('sub-audio block follows portraitSubAudioAlign', (tester) async {
    _setSurface(tester);
    useAppStore().set(
        useAppStore().state.copyWith(desktopCenterZonePhoneMode: true));
    // Seed the 副音 store directly: `await initialized` would deadlock under
    // testWidgets' fake-async (the load path hits the real Drift DB).
    final bg = useBackgroundPlaybackStore();
    bg.set(bg.state.copyWith(enabled: true, quickBarEnabled: true));
    useControlGroupStore().set(
        useControlGroupStore().state.copyWith(group: PlayerControlGroup.background));

    Future<void> pumpWith(PortraitBarAlign a) async {
      useAppStore()
          .set(useAppStore().state.copyWith(portraitSubAudioAlign: a));
      await tester.pumpWidget(_harness(_bar()));
      await tester.pumpAndSettle();
    }

    Rect block() => tester.getRect(find.byKey(const ValueKey('bg_quick_bar')));

    await pumpWith(PortraitBarAlign.left);
    expect(block().left, lessThanOrEqualTo(1.0),
        reason: 'left: 副音 block hugs the left edge');
    expect(block().right, lessThan(400.0),
        reason: 'the block shrink-wraps, never the full bar width');

    await pumpWith(PortraitBarAlign.center);
    final Rect c = block();
    expect((c.left - (400.0 - c.right)).abs(), lessThan(2.0),
        reason: 'center: the 副音 block is centred as a whole');

    await pumpWith(PortraitBarAlign.right);
    expect(400.0 - block().right, lessThanOrEqualTo(1.0),
        reason: 'right: 副音 block hugs the right edge');
  });

  testWidgets('the dialog exposes two rows and commits each group live',
      (tester) async {
    _setSurface(tester);
    useAppStore().set(useAppStore().state.copyWith(
          portraitPlaybackAlign: PortraitBarAlign.center,
          portraitSubAudioAlign: PortraitBarAlign.center,
        ));
    await tester.pumpWidget(_harness(const PortraitBarAlignDialog()));
    await tester.pumpAndSettle();

    expect(find.byType(SegmentedButton<PortraitBarAlign>), findsNWidgets(2),
        reason: 'one row for the playback group, one for the 副音 group');

    // First row → LEFT, second row → RIGHT.
    await tester.tap(find.text('Left').first);
    await tester.pump();
    await tester.tap(find.text('Right').last);
    await tester.pump();

    final AppState s = useAppStore().state;
    expect(s.portraitPlaybackAlign, PortraitBarAlign.left);
    expect(s.portraitSubAudioAlign, PortraitBarAlign.right);
  });
}
