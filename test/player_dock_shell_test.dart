import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/pages/home/player_dock_shell.dart';

/// Regression: toggling the playlist dock must not re-create the player
/// subtree.
///
/// WHY (flutter/flutter #177693 / #188500, the #182444 family): the player
/// subtree owns a shared GlobalKey (production: the side panel's box, before it
/// became a per-mount key) and a Tooltip whose `OverlayPortal` grafts into the
/// root overlay. Home used to return a DIFFERENT shell shape for the dock
/// on/off states (`Stack` vs `Row > Expanded > Stack`), so the whole player
/// subtree was deactivated and a new one mounted. The new panel box then
/// re-took the still-inactive GlobalKey element
/// (`Element._retakeInactiveElement`), which re-activated the OLD, OPEN
/// tooltip's `OverlayPortal` from inside a `LayoutBuilder` layout callback:
/// `_RenderLayoutBuilder was mutated in performLayout`, then the element tree is
/// poisoned (`Lost connection to device`, bogus
/// `RenderFlex overflowed by 97890 pixels`).
///
/// `PlayerDockShell` keeps ONE shape; the dock only adds/removes trailing
/// children, so the player element survives every toggle.

/// A SHARED key on purpose: this file locks (a) the structural rule that keeps
/// the player element alive and (b) the framework hazard that rule avoids. Both
/// assertions use the same key so the pair stays meaningful.
final GlobalKey _kPanelKey = GlobalKey(debugLabel: 'test-side-panel');

/// Mimics the parts of the player subtree that trip the graft: a reused
/// [_kPanelKey]-carrying box built from inside a `LayoutBuilder` (like
/// `CircleSliderLayout`), plus a live Tooltip overlay.
class _PlayerAreaProxy extends StatelessWidget {
  const _PlayerAreaProxy();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            key: _kPanelKey,
            width: 240,
            height: 120,
            child: Tooltip(
              message: 'panel action',
              child: IconButton(
                icon: const Icon(Icons.check),
                onPressed: () {},
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Home's former behaviour: the player slot's parent SHAPE flips with the dock,
/// which deactivates and re-creates the whole player subtree.
class _LegacyShapeFlip extends StatelessWidget {
  const _LegacyShapeFlip({required this.dock, required this.playerArea});

  final bool dock;
  final Widget playerArea;

  @override
  Widget build(BuildContext context) {
    // The same top-level LayoutBuilder Home uses: its builder runs during
    // layout, so the deactivation and the re-inflation both happen inside a
    // layout callback.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (!dock) {
          return Stack(children: <Widget>[playerArea]);
        }
        return Row(
          children: <Widget>[
            Expanded(child: Stack(children: <Widget>[playerArea])),
          ],
        );
      },
    );
  }
}

Widget _harness(ValueNotifier<bool> dock, Widget Function(bool) build) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      backgroundColor: Colors.black,
      body: ValueListenableBuilder<bool>(
        valueListenable: dock,
        builder: (BuildContext context, bool docked, _) => build(docked),
      ),
    ),
  );
}

/// Opens the tooltip so its OverlayPortal has an active overlay child — the
/// activation during a graft is what trips the assert. Programmatic (no pointer
/// events) so the test stays independent of mouse-tracker state.
Future<void> _openTooltip(WidgetTester tester) async {
  tester.state<TooltipState>(find.byType(Tooltip)).ensureTooltipVisible();
  await tester.pumpAndSettle();
  expect(find.text('panel action'), findsOneWidget,
      reason: 'the tooltip must actually be open to exercise the graft path');
}

void main() {
  testWidgets('PlayerDockShell keeps the panel element across dock toggles',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final ValueNotifier<bool> dock = ValueNotifier<bool>(false);
    addTearDown(dock.dispose);

    await tester.pumpWidget(_harness(
      dock,
      (bool docked) => PlayerDockShell(
        playerArea: const _PlayerAreaProxy(),
        dockSlots: docked
            ? const <Widget>[
                SizedBox(width: 1, child: ColoredBox(color: Color(0xFF333333))),
                SizedBox(width: 200, child: ColoredBox(color: Color(0xFF1E1E1E))),
              ]
            : const <Widget>[],
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await _openTooltip(tester);

    final Element panelBefore = tester.element(find.byKey(_kPanelKey));

    // Dock appears: the player area must be preserved, not re-created.
    dock.value = true;
    await tester.pump();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.element(find.byKey(_kPanelKey)), same(panelBefore),
        reason: 'the shell must not re-parent/re-create the player subtree');
    expect(find.text('panel action'), findsOneWidget);

    // Dock disappears again.
    dock.value = false;
    await tester.pump();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.element(find.byKey(_kPanelKey)), same(panelBefore));
  });

  testWidgets('the player area fills the shell in both dock states',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final ValueNotifier<bool> dock = ValueNotifier<bool>(false);
    addTearDown(dock.dispose);

    await tester.pumpWidget(_harness(
      dock,
      (bool docked) => PlayerDockShell(
        playerArea: const ColoredBox(color: Colors.red, key: ValueKey('area')),
        dockSlots: docked
            ? const <Widget>[
                SizedBox(width: 200, child: ColoredBox(color: Colors.blue)),
              ]
            : const <Widget>[],
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(const ValueKey('area'))),
        const Size(1280, 720));

    dock.value = true;
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const ValueKey('area'))),
        const Size(1080, 720));
  });

  // Mechanism lock (kept LAST: the failing frame poisons the binding's element
  // tree and mouse tracker, so nothing may run after it in this isolate).
  testWidgets('the legacy shape flip grafts the panel key mid-layout (hazard)',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final ValueNotifier<bool> dock = ValueNotifier<bool>(false);
    addTearDown(dock.dispose);

    await tester.pumpWidget(_harness(
      dock,
      (bool docked) => _LegacyShapeFlip(
        dock: docked,
        playerArea: const _PlayerAreaProxy(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await _openTooltip(tester);

    // Capture instead of failing: the hazard deliberately breaks the frame.
    final List<FlutterErrorDetails> errors = <FlutterErrorDetails>[];
    final void Function(FlutterErrorDetails)? previousOnError =
        FlutterError.onError;
    FlutterError.onError = errors.add;
    try {
      dock.value = true;
      await tester.pump();
      await tester.pump();
    } finally {
      FlutterError.onError = previousOnError;
    }

    final String reported =
        errors.map((FlutterErrorDetails d) => d.exception.toString()).join('\n');
    expect(reported, contains('_RenderLayoutBuilder was mutated'),
        reason: 'the shape flip must trip the LayoutBuilder mutation assert');
  });
}
