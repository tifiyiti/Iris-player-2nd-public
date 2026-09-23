import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/widgets/dialogs/show_phone_one_handed_scrubber_kind_dialog.dart';
import 'package:provider/provider.dart';
import 'package:zustand/zustand.dart';

// One long-lived tree across phases (flutter_zustand cross-test store
// lifecycle lesson): the dialog is reopened with different flags and the
// same provider scope keeps carrying the app store.
//
// Requirement #6: the retired designs (arc/timeLens/snake) are NEVER offered
// anymore — every phase only ever sees Ring dial and (opted-in) Simple
// circle arc.
//
// NOTE: the scope deliberately does NOT dispose the global StoreLocator on
// unmount ([StoreScope] does, fire-and-forget) — the app store created here
// lives in that locator, so tearing it down races the next test's writes.
Widget _providerScope(Widget child) => InheritedProvider<StoreLocator>.value(
      value: StoreLocator(),
      startListening: (InheritedContext<StoreLocator?> e, StoreLocator value) {
        final sub = value.changes.listen((_) => e.markNeedsNotifyDependents());
        return sub.cancel;
      },
      lazy: false,
      child: child,
    );

Widget _harness({
  required bool includeDial,
  bool includeClassic = false,
}) {
  return _providerScope(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () => showPhoneOneHandedScrubberKindDialog(
                context,
                includeDial: includeDial,
                includeClassic: includeClassic,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _close(WidgetTester tester) async {
  await tester.tap(find.text('关闭'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('scrubber-kind dialog gates Ring dial behind includeDial',
      (tester) async {
    // Phase 1: legacy default hides the metadata-only Ring dial row AND the
    // retired designs are gone entirely.
    await tester.pumpWidget(_harness(includeDial: false));
    await tester.pump();
    await _open(tester);
    expect(find.text('双环拨盘'), findsNothing);
    expect(find.text('Ring scrubber'), findsNothing,
        reason: 'arc is fully retired (requirement #6)');
    expect(find.text('Time lens scrubber'), findsNothing,
        reason: 'timeLens is fully retired (requirement #6)');
    expect(find.text('Snake 5-axis'), findsNothing,
        reason: 'snake is fully retired (requirement #6)');
    await _close(tester);

    // Phase 2: the metadata-driven binding opts in.
    await tester.pumpWidget(_harness(includeDial: true));
    await tester.pump();
    await _open(tester);
    expect(find.text('双环拨盘'), findsOneWidget);
  });

  testWidgets('meta mode offers only Ring dial + Simple circle arc',
      (tester) async {
    await tester.pumpWidget(_harness(
      includeDial: true,
      includeClassic: true,
    ));
    await tester.pump();
    await _open(tester);

    // Retired designs are hidden; dial + classic remain.
    expect(find.text('Ring scrubber'), findsNothing);
    expect(find.text('Time lens scrubber'), findsNothing);
    expect(find.text('Snake 5-axis'), findsNothing);
    expect(find.text('双环拨盘'), findsOneWidget);
    expect(find.text('简易圆弧'), findsOneWidget);

    // Choosing the classic circle slider persists and renders as legacy.
    await tester.tap(find.text('简易圆弧'));
    await tester.pumpAndSettle();
    expect(useAppStore().state.phoneOneHandedScrubberKind,
        PhoneOneHandedScrubberKind.classic);
  });
}
