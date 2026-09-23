import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/engine/background_playback_engine.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/features/background_playback/view/segment_align_edit_panel.dart';
import 'package:iris/globals.dart'
    show apbEditorPanelKeyNotifier, sidePanelKeyNotifier;
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/models/store/app_state.dart' show PlayerBackend;
import 'package:iris/pages/player/control_bar/control_bar_layout/circle_slider_layout.dart';
import 'package:iris/pages/player/control_bar/control_bar_layout/control_bar_controls.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:provider/provider.dart';
import 'package:zustand/zustand.dart';

/// Regression: the APB align editor's side panel must NOT share the normal
/// one-handed panel's [GlobalKey].
///
/// WHY (flutter/flutter #177693 / #188500, the #182444 family): `ControlsOverlay`
/// swaps `SegmentAlignEditPanel` and `CircleSliderLayout` in and out. When both
/// put their panel box under the SAME GlobalKey, exiting the editor grafts the
/// whole keyed subtree (editor bottom bar = many Tooltips) into the normal
/// panel. That graft's `_activateRecursively` runs from inside
/// `CircleSliderLayout`'s top `LayoutBuilder` layout callback, so an OPEN
/// Tooltip's `OverlayPortal` re-adds its deferred child mid-layout:
/// `_RenderLayoutBuilder was mutated in performLayout`, then the element tree is
/// poisoned (red screen / `Lost connection to device`).
///
/// The editor now owns [apbEditorPanelKey]; these tests lock the distinct-key
/// contract, prove the REAL editor uses it, and prove the swap is
/// exception-free while a Tooltip is open.
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

/// Manual scope (no dispose): the shared [StoreLocator] must survive across the
/// tests in this file, unlike `StoreScope` which closes it on unmount.
Widget _shell(Widget body, BackgroundPlaybackEngine engine) =>
    InheritedProvider<StoreLocator>.value(
      value: StoreLocator(),
      startListening: (InheritedContext<StoreLocator?> e, StoreLocator value) {
        final sub = value.changes.listen((_) => e.markNeedsNotifyDependents());
        return sub.cancel;
      },
      lazy: false,
      child: Provider<MediaPlayer>.value(
        value: _player(),
        child: ChangeNotifierProvider<BackgroundPlaybackEngine>.value(
          value: engine,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Align(alignment: Alignment.bottomRight, child: body),
            ),
          ),
        ),
      ),
    );

/// A SHARED key on purpose: this file also locks the framework hazard the
/// production per-mount keys avoid (a keyed box carrying an OPEN tooltip being
/// swapped out while the incoming panel is built by a `LayoutBuilder`).
final GlobalKey _kEditorStandInKey = GlobalKey(debugLabel: 'editor-stand-in');

/// Stand-in for the editor panel box: a keyed box around an OPEN Tooltip.
Widget _editorStandIn(BuildContext context) => SizedBox(
      key: _kEditorStandInKey,
      width: 300,
      height: 300,
      child: Column(
        children: <Widget>[
          Tooltip(
            message: 'editor action',
            waitDuration: Duration.zero,
            child: IconButton(
              icon: const Icon(Icons.check),
              onPressed: () {},
            ),
          ),
        ],
      ),
    );

Widget _normalPanel() => CircleSliderLayout(
      width: 1280,
      panelPercent: 30,
      controls: _controls(),
      scrubberBuilder: (double? span, double? dialPx) =>
          const SizedBox.shrink(),
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

  late BackgroundPlaybackEngine engine;
  setUp(() {
    engine = BackgroundPlaybackEngine(
      backend: PlayerBackend.mediaKit,
      attachNative: false,
    );
    useAppStore().set(useAppStore().state.copyWith(
          useMetadataSettings: true,
          useLegacyStoragePersistence: false,
        ));
    final bg = useBackgroundPlaybackStore();
    bg.set(bg.state.copyWith(
      enabled: true,
      quickBarEnabled: true,
      segmentEditMode: true,
    ));
  });
  tearDown(() => engine.dispose());

  testWidgets('the editor and the normal panel publish distinct per-mount keys',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _shell(const SegmentAlignEditPanel(isSide: true), engine),
    );
    await tester.pumpAndSettle();
    final GlobalKey? editorKey = apbEditorPanelKeyNotifier.value;
    expect(editorKey, isNotNull);
    expect(sidePanelKeyNotifier.value, isNull,
        reason: 'no normal panel is mounted while the editor owns the side');

    await tester.pumpWidget(_shell(_normalPanel(), engine));
    await tester.pumpAndSettle();
    final GlobalKey? panelKey = sidePanelKeyNotifier.value;
    expect(panelKey, isNotNull);
    expect(panelKey, isNot(same(editorKey)),
        reason: 'the two panels must never share one key object');
    expect(apbEditorPanelKeyNotifier.value, isNull,
        reason: 'the editor key must be retracted once its panel unmounts');
  });

  testWidgets('the REAL side editor mounts under the published key',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_shell(
      const SegmentAlignEditPanel(isSide: true),
      engine,
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final GlobalKey? editorKey = apbEditorPanelKeyNotifier.value;
    expect(editorKey, isNotNull);
    expect(find.byKey(editorKey!), findsOneWidget,
        reason: 'the editor panel box must publish its own key');
    expect(sidePanelKeyNotifier.value, isNull,
        reason: 'the editor must never borrow the normal panel key');
  });

  testWidgets('editor -> normal panel swap never grafts an OPEN tooltip',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_shell(Builder(builder: _editorStandIn), engine));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Show the tooltip overlay so its OverlayPortal has an active location —
    // the activation during the swap is what trips the assert.
    final TestGesture mouse =
        await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byIcon(Icons.check)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('editor action'), findsOneWidget,
        reason: 'the tooltip must actually be open to exercise the graft path');

    await tester.pumpWidget(_shell(_normalPanel(), engine));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'the swap must not re-activate the keyed subtree mid-layout');
  });
}
