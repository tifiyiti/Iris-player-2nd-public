import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/control_bar/control_bar_layout/circle_slider_layout.dart';
import 'package:iris/pages/player/control_bar/control_bar_layout/control_bar_controls.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:provider/provider.dart';

/// Regression: the one-handed side panel's box must own a PER-MOUNT key, never
/// a shared one.
///
/// WHY (flutter/flutter #177693 / #188500, the #182444 family): a shared
/// GlobalKey lets a NEW panel element re-take the OLD (deactivated) one
/// (`Element._retakeInactiveElement`, `framework.dart:4481`). Re-activating it
/// re-activates every `OverlayPortal` inside — here an OPEN Tooltip — and
/// `_OverlayPortalElement.activate` (`overlay.dart:2417`) grafts the deferred
/// child into the root overlay BEFORE the new parent is attached, so the
/// mutation locks onto a render object with no actively-laying-out ancestor:
/// `_RenderLayoutBuilder was mutated in performLayout`, then a poisoned element
/// tree, a bogus `RenderFlex overflowed by 97890 pixels` and a dead process.
///
/// A per-mount key object can never be re-taken, so this flip must stay clean
/// even while a tooltip is open.
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

/// Mimics Home's dock wrapper: the player slot's parent SHAPE flips, so the
/// whole player subtree (here: the panel) is deactivated and re-created.
class _ShapeFlipHarness extends StatelessWidget {
  const _ShapeFlipHarness({required this.dock, required this.child});

  final ValueListenable<bool> dock;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: dock,
      builder: (BuildContext context, bool docked, _) => LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          if (!docked) {
            return Stack(children: <Widget>[child]);
          }
          return Row(
            children: <Widget>[
              Expanded(child: Stack(children: <Widget>[child])),
            ],
          );
        },
      ),
    );
  }
}

Widget _harness(ValueNotifier<bool> dock) => StoreScope(
      child: Provider<MediaPlayer>.value(
        value: _player(),
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: _ShapeFlipHarness(
              dock: dock,
              child: Align(
                alignment: Alignment.bottomRight,
                child: CircleSliderLayout(
                  width: 1280,
                  panelPercent: 30,
                  controls: _controls(),
                  scrubberBuilder: (double? span, double? dialPx) => Align(
                    alignment: Alignment.topLeft,
                    child: Tooltip(
                      key: const ValueKey('dial-tooltip'),
                      message: 'dial action',
                      child: IconButton(
                        icon: const Icon(Icons.check),
                        onPressed: () {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

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

  testWidgets('a dock-style shape flip never grafts the open panel tooltip',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final ValueNotifier<bool> dock = ValueNotifier<bool>(false);
    addTearDown(dock.dispose);

    await tester.pumpWidget(_harness(dock));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Open a tooltip INSIDE the panel so its OverlayPortal has an active
    // overlay child — the activation during a graft is what trips the assert.
    // Programmatic (no pointer events) so the test is independent of
    // mouse-tracker state.
    tester
        .state<TooltipState>(find.byKey(const ValueKey('dial-tooltip')))
        .ensureTooltipVisible();
    await tester.pumpAndSettle();
    expect(find.text('dial action'), findsOneWidget);

    dock.value = true;
    await tester.pump();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'the panel must never be re-activated mid-layout');

    dock.value = false;
    await tester.pump();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
