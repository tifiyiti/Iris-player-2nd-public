import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/globals.dart' show sidePanelKeyNotifier;
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/control_bar/control_bar_layout/circle_slider_layout.dart';
import 'package:iris/pages/player/control_bar/control_bar_layout/control_bar_controls.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:provider/provider.dart';
import 'package:zustand/zustand.dart';

/// Regression: the one-handed side panel's shell must keep the SAME shape as
/// the 副音 quick column / resize affordances toggle.
///
/// WHY (flutter/flutter #177693 / #188500, the #182444 family): the
/// tooltip-bearing panel sits under the layout's top `LayoutBuilder`. Moving it
/// between different parents (bare vs `Row`, changing child counts) re-activates
/// its `Tooltip` `OverlayPortal`s while the `LayoutBuilder` is laying out and
/// trips `_RenderLayoutBuilder was mutated in performLayout`, after which the
/// element tree is poisoned (`Lost connection to device`). The fix renders one
/// stable Row/Stack shape; this test locks that the panel element is NOT
/// re-parented (its `Element` identity survives) and nothing throws.
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

  tearDown(() => StoreLocator().delete(BackgroundPlaybackStore));

  testWidgets('toggling the quick column never re-parents the tooltip panel',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final bg = useBackgroundPlaybackStore();
    await bg.initialized;
    bg.set(bg.state.copyWith(enabled: true, quickBarEnabled: true));

    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final Finder panel = find.byKey(sidePanelKeyNotifier.value!);
    final Element panelBefore = tester.element(panel);
    final Element parentBefore = _directParent(panelBefore);
    int rowAncestors() =>
        find.ancestor(of: panel, matching: find.byType(Row)).evaluate().length;
    int stackAncestors() => find
        .ancestor(of: panel, matching: find.byType(Stack))
        .evaluate()
        .length;
    final int rowsBefore = rowAncestors();
    final int stacksBefore = stackAncestors();
    expect(rowsBefore, greaterThan(0));
    expect(stacksBefore, greaterThan(0));

    // Collapse the quick column: the shell shape must not change, so the panel
    // is not relocated into a new parent (which would `activate` its Tooltip
    // OverlayPortals mid-layout).
    bg.set(bg.state.copyWith(quickBarEnabled: false));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.element(panel),
      same(panelBefore),
      reason: 'the panel element must survive (GlobalKey relocation)',
    );
    expect(
      _directParent(tester.element(panel)),
      same(parentBefore),
      reason: 'the panel must NOT be re-parented (OverlayPortal graft)',
    );
    expect(rowAncestors(), rowsBefore,
        reason: 'the shell Row must stay in the tree when the quick bar hides');
    expect(stackAncestors(), stacksBefore);

    // And back on again.
    bg.set(bg.state.copyWith(quickBarEnabled: true));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.element(panel), same(panelBefore));
    expect(_directParent(tester.element(panel)), same(parentBefore));
    expect(rowAncestors(), rowsBefore);
    expect(stackAncestors(), stacksBefore);
  });
}

/// The immediate ancestor of [element] (`Element.parent` is private).
Element _directParent(Element element) {
  late Element parent;
  element.visitAncestorElements((Element ancestor) {
    parent = ancestor;
    return false;
  });
  return parent;
}
