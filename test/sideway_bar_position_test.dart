import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/globals.dart' show sidePanelKeyNotifier;
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/pages/player/control_bar/control_bar_layout/circle_slider_layout.dart';
import 'package:iris/pages/player/control_bar/control_bar_layout/control_bar_controls.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/platform.dart' show debugIsMobilePlatformOverride;
import 'package:iris/widgets/controls/balanced_button_wrap.dart';
import 'package:provider/provider.dart';

/// The one-handed side panel's bottom button BLOCK must hug the panel edge
/// facing the screen centre (right-docked → left) and slide toward the outer
/// window edge with the shared `sidewayBarPos` knob — never leaving the panel.
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

Widget _harness() => StoreScope(
      child: Provider<MediaPlayer>.value(
        value: _player(),
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomRight,
              child: CircleSliderLayout(
                width: 1280,
                panelPercent: 30,
                controls: _controls(),
                scrubberBuilder: (double? span, double? dialPx) =>
                    const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );

/// Seeds a right-docked phone-landscape one-handed panel with a given block
/// position. Called BEFORE pumping.
void _seedSidePanel({required double sidewayBarPos}) {
  final store = useAppStore();
  store.set(store.state.copyWith(
    phoneLandscapeUseMode: PhoneLandscapeUseMode.rightSide,
    mobileSidePositionH: PhoneSidePositionH.right,
    phoneOneHandedScrubberKind: PhoneSideScrubberKind.classic,
    runtimeOrientation: ScreenOrientation.landscape,
    sidewayPanelWidthPct: 30.0,
    sidewayPanelHeightPct: 90.0,
    sidewayBarPos: sidewayBarPos,
  ));
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
    useAppStore().set(useAppStore().state.copyWith(
          useMetadataSettings: true,
          useLegacyStoragePersistence: false,
        ));
  });

  testWidgets(
      'bottom button block hugs the screen-centre edge (right-docked, pos 0)',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    debugIsMobilePlatformOverride = true;
    addTearDown(() => debugIsMobilePlatformOverride = null);

    _seedSidePanel(sidewayBarPos: 0.0);

    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final Rect panel = tester.getRect(find.byKey(sidePanelKeyNotifier.value!));
    final Rect block = tester.getRect(find.byType(BalancedButtonWrap));
    expect(block.left - panel.left, lessThan(8),
        reason: 'right-docked + pos 0: block hugs the centre-facing LEFT edge');
    // Balanced rows: the block never leaves the panel.
    expect(block.right, lessThanOrEqualTo(panel.right + 0.01));
  });

  testWidgets('the position knob slides the block to the outer window edge',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    debugIsMobilePlatformOverride = true;
    addTearDown(() => debugIsMobilePlatformOverride = null);

    _seedSidePanel(sidewayBarPos: 1.0);

    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final Rect panel = tester.getRect(find.byKey(sidePanelKeyNotifier.value!));
    final Rect block = tester.getRect(find.byType(BalancedButtonWrap));
    expect(panel.right - block.right, lessThan(8),
        reason: 'pos 1 slides the block to the outer (window) edge');
    expect(block.left, greaterThanOrEqualTo(panel.left - 0.01));
  });
}
