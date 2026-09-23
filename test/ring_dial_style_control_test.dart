import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/widgets/controls/ring_dial_style_control.dart';

/// RingDialStyleControl card-content contract:
///
///  * ONE palette row — four mini sector-donut swatches in the LOCKED order
///    mono → cold → warm → rainbow; tapping a swatch updates
///    `AppState.ringDialPalette` and moves the selection marker;
///  * a shared Inner/Outer side segmented button (flips ring);
///  * FOUR sliders bound to AppState: Height% [30,100] of the
///    screen-top↔button-bar span, Ring slot [0,100],
///    Outer% [80,100], Inner% [30,81];
///  * every slider mirrors its state field live (two-way).
void main() {
  testWidgets('palette order/selection + side/axis + five bound sliders',
      (tester) async {
    await tester.pumpWidget(
      StoreScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 276,
                height: 324,
                child: RingDialStyleControl(showControl: () {}),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // ── Palette row: four swatches, fixed left-to-right order ──
    for (final String name in <String>['mono', 'cold', 'warm', 'rainbow']) {
      expect(find.byKey(Key('ring-dial-palette-$name')), findsOneWidget,
          reason: 'swatch $name must exist');
    }
    final double monoX =
        tester.getCenter(find.byKey(const Key('ring-dial-palette-mono'))).dx;
    final double coldX =
        tester.getCenter(find.byKey(const Key('ring-dial-palette-cold'))).dx;
    final double warmX =
        tester.getCenter(find.byKey(const Key('ring-dial-palette-warm'))).dx;
    final double rainbowX =
        tester.getCenter(find.byKey(const Key('ring-dial-palette-rainbow'))).dx;
    expect(monoX < coldX && coldX < warmX && warmX < rainbowX, isTrue,
        reason: 'swatch order must be mono → cold → warm → rainbow');

    // Default selection marker sits on mono.
    expect(find.byKey(const Key('ring-dial-palette-selected')), findsOneWidget);
    expect(
      tester.getCenter(find.byKey(const Key('ring-dial-palette-selected'))),
      tester.getCenter(find.byKey(const Key('ring-dial-palette-mono'))),
      reason: 'default palette is mono',
    );

    // ── Tapping a swatch switches the palette and the selection marker ──
    await tester.tap(find.byKey(const Key('ring-dial-palette-rainbow')));
    await tester.pump();
    expect(useAppStore().state.ringDialPalette, RingDialPalette.rainbow);
    expect(
      tester.getCenter(find.byKey(const Key('ring-dial-palette-selected'))),
      tester.getCenter(find.byKey(const Key('ring-dial-palette-rainbow'))),
      reason: 'selection must follow the tapped swatch',
    );

    // ── Shared side toggle flips both components at once ──
    expect(useAppStore().state.ringDialSide, DialSide.inner);
    await tester.tap(find.text('Outer'));
    await tester.pump();
    expect(useAppStore().state.ringDialSide, DialSide.outer);

    // ── Four sliders in declaration order with exact bands ──
    final List<Slider> sliders =
        tester.widgetList<Slider>(find.byType(Slider)).toList();
    expect(sliders.length, 4,
        reason: 'Height / Ring slot / Outer / Inner');

    final AppState s = useAppStore().state;
    void expectBand(int i,
        {required double min, required double max, required double value}) {
      expect(sliders[i].min, min, reason: 'slider $i min');
      expect(sliders[i].max, max, reason: 'slider $i max');
      expect(sliders[i].value, closeTo(value, 1e-9), reason: 'slider $i value');
    }

    expectBand(0, min: 30, max: 100, value: s.ringDialHeightPct * 100);
    expectBand(1, min: 0, max: 100, value: s.ringDialRingSlotT * 100);
    expectBand(2, min: 80, max: 100, value: s.ringDialOuterRadius * 100);
    expectBand(3, min: 30, max: 81, value: s.ringDialInnerRadius * 100);

    // ── Live two-way binding: dragging updates the store ──
    final double beforeH = useAppStore().state.ringDialHeightPct;
    await tester.drag(find.byType(Slider).first, const Offset(-60, 0));
    await tester.pump();
    expect(useAppStore().state.ringDialHeightPct, lessThan(beforeH),
        reason: 'dragging the height slider left must shrink heightPct');

    // ── VM progress-lock switch reflects and flips the store ──
    final Finder sw = find.byKey(const Key('ring-dial-vm-progress-lock'));
    expect(sw, findsOneWidget,
        reason: 'the VM progress-lock switch must exist');
    expect(useAppStore().state.ringDialVmProgressLock, isTrue,
        reason: 'the feature ships enabled');
    await tester.ensureVisible(sw);
    await tester.tap(sw);
    await tester.pump();
    expect(useAppStore().state.ringDialVmProgressLock, isFalse,
        reason: 'tapping the switch flips the setting off');
  });

  testWidgets('style card anchors beside the panel centre-facing edge',
      (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // A stand-in panel occupying the RIGHT side (right-handed layout):
    // its inner edge is the LEFT edge, so the card must land fully LEFT of
    // the panel and never overlap it.
    await tester.pumpWidget(
      StoreScope(
        child: MaterialApp(home: Scaffold(body: Container())),
      ),
    );
    await tester.pump();

    final Rect panel = Rect.fromLTWH(500, 100, 280, 400);
    final Rect card = ringDialStyleCardRect(
      panel: panel,
      screen: const Size(800, 600),
      innerIsLeft: true,
    );
    expect(card.right, lessThanOrEqualTo(panel.left + 0.01),
        reason: 'card must emerge from the panel inner edge, not cover it');
    expect(card.left, greaterThanOrEqualTo(8),
        reason: 'card stays on screen');
    expect(card.width, kStyleCardWidth);
    expect(card.top, inExclusiveRange(0.0, 600.0));
    expect(card.bottom, lessThanOrEqualTo(600.0));
  });
}
