import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/widgets/controls/ring_dial_style_control.dart';

// Regression: the dial style popover fell off-screen on short viewports.
// Popover 0.3.1 flips top→bottom but never CLAMPS (top lands at
// attach.top − height), so a fixed 340px bubble overflowed phone-landscape /
// small desktop windows whenever neither side had room.
void main() {
  testWidgets('style popover stays fully inside a short viewport',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 640); // 400×320 logical @2x
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(StoreScope(
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            // Anchor from the BUTTON's own context — production anchors via
            // the small PopupMenuItem, not a full-screen ancestor.
            child: Builder(
              builder: (BuildContext btnCtx) => FilledButton(
                onPressed: () => showRingDialStyleControlPopover(btnCtx, () {}),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));

    // Deferred l10n delegates load async — settle before tapping.
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final Rect r = tester.getRect(find.byType(SingleChildScrollView));
    expect(r.top, greaterThanOrEqualTo(0), reason: 'popover top on-screen');
    expect(r.bottom, lessThanOrEqualTo(320),
        reason: 'popover bottom on-screen');
    expect(r.left, greaterThanOrEqualTo(0));
    expect(r.right, lessThanOrEqualTo(400));
  });
}
