import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/widgets/a11y_tooltip.dart';

/// AXTree stability: control-bar buttons must be isolated in a semantics
/// container so Tooltip's OverlayPortal graft never leaks across siblings,
/// and the tooltip must switch to tap-only as soon as ANY assistive client
/// listens. Gating condition: `semanticsEnabled || accessibleNavigation` —
/// Windows UIA clients (NVDA et al.) activate semantics WITHOUT setting
/// `accessibleNavigation`, so hover tooltips must die the moment semantics
/// activates, or they graft into the root overlay mid-playback (#182444).
void main() {
  testWidgets('a11yTooltip wraps child in Semantics container', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => a11yTooltip(
              context: context,
              message: 'test tip',
              child: const Icon(Icons.play_arrow),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final semantics = tester.widgetList<Semantics>(find.byType(Semantics));
    expect(
      semantics.any((s) => s.container == true),
      isTrue,
      reason: 'a11yTooltip must create a Semantics container boundary',
    );
    expect(find.byType(Tooltip), findsOneWidget);
  });

  testWidgets('a11yTooltip goes tap-only the moment semantics activates '
      '(NVDA/UIA path, no accessibleNavigation)',
      // The test-binding default force-enables semantics; opt out so the
      // gate actually starts OFF.
      semanticsEnabled: false, (tester) async {
    Widget harness() => MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => a11yTooltip(
                context: context,
                message: 'tip',
                child: const Icon(Icons.play_arrow),
              ),
            ),
          ),
        );

    // Gate off: platform semantics OFF + no accessibleNavigation.
    tester.platformDispatcher.semanticsEnabledTestValue = false;
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).triggerMode,
      isNull,
      reason: 'with no assistive client, tooltip uses default triggerMode',
    );

    // NVDA/UIA path: semanticsEnabled flips on WITHOUT accessibleNavigation.
    tester.platformDispatcher.semanticsEnabledTestValue = true;
    await tester.pumpAndSettle();
    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).triggerMode,
      TooltipTriggerMode.tap,
      reason: 'semanticsEnabled alone must engage tap-only mode',
    );

    // Client detaches → hover tooltips return.
    tester.platformDispatcher.clearSemanticsEnabledTestValue();
    await tester.pumpAndSettle();
    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).triggerMode,
      isNull,
      reason: 'detaching the client must restore the default trigger',
    );
  });

  testWidgets('a11yTooltip uses tap trigger when accessibleNavigation is true',
      // Opt out of the default forced semantics so the OR is exercised
      // through the features path only.
      semanticsEnabled: false, (tester) async {
    // Pin semantics OFF so the OR is exercised through the features path.
    tester.platformDispatcher.semanticsEnabledTestValue = false;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(accessibleNavigation: true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => a11yTooltip(
              context: context,
              message: 'tip',
              child: const Icon(Icons.play_arrow),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).triggerMode,
      TooltipTriggerMode.tap,
      reason: 'when a11y on, tooltip must be tap-only',
    );
    tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
    tester.platformDispatcher.clearSemanticsEnabledTestValue();
  });

  testWidgets('a11yTooltipIconButton is semantics-container isolated',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => a11yTooltipIconButton(
              context: context,
              tooltip: 'play',
              icon: const Icon(Icons.play_arrow),
              onPressed: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(IconButton), findsOneWidget);
    final semantics = tester.widgetList<Semantics>(find.byType(Semantics));
    expect(semantics.any((s) => s.container == true), isTrue);
    expect(find.byType(Tooltip), findsOneWidget);
  });
}
