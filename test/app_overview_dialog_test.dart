import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/store/warning_dialogs.dart';
import 'package:iris/widgets/dialogs/show_app_overview_dialog.dart';

Future<void> pumpHarness(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(
    locale: Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(),
  ));
  // Deferred l10n delegates load async — settle once before opening dialogs.
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'first run shows the tour with a checked dont-ask and suppresses on OK',
      (tester) async {
    await pumpHarness(tester);
    String? suppressedId;
    final future = showAppOverviewDialog(
      tester.element(find.byType(Scaffold)),
      firstRun: true,
      isSuppressedOverride: (_) => false,
      onSuppressOverride: (id) => suppressedId = id,
    );
    await tester.pump();

    expect(find.text('What makes IRIS different'), findsOneWidget);
    final checkbox = find.byType(CheckboxListTile);
    expect(checkbox, findsOneWidget);
    // Default-checked per the one-time-tour contract.
    expect(tester.widget<CheckboxListTile>(checkbox).value, isTrue);

    await tester.tap(find.text('OK'));
    await tester.pump();
    await future;
    expect(suppressedId, kWarningAppOverview);
  });

  testWidgets('unchecking the box does not suppress', (tester) async {
    await pumpHarness(tester);
    String? suppressedId;
    final future = showAppOverviewDialog(
      tester.element(find.byType(Scaffold)),
      firstRun: true,
      isSuppressedOverride: (_) => false,
      onSuppressOverride: (id) => suppressedId = id,
    );
    await tester.pump();

    final checkbox = find.byType(CheckboxListTile);
    await tester.ensureVisible(checkbox);
    await tester.pumpAndSettle();
    await tester.tap(checkbox);
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pump();
    await future;
    expect(suppressedId, isNull);
  });

  testWidgets(
      'barrier dismissal with the box checked still suppresses (no re-show)',
      (tester) async {
    await pumpHarness(tester);
    String? suppressedId;
    final future = showAppOverviewDialog(
      tester.element(find.byType(Scaffold)),
      firstRun: true,
      isSuppressedOverride: (_) => false,
      onSuppressOverride: (id) => suppressedId = id,
    );
    await tester.pump();
    expect(find.text('What makes IRIS different'), findsOneWidget);

    // Dismiss WITHOUT OK (tap the barrier). The default-checked box must still
    // persist suppression, or the tour returns every launch and blocks every
    // player shortcut behind its modal route.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await future;
    expect(suppressedId, kWarningAppOverview);
  });

  testWidgets('a suppressed id skips the first-run UI entirely', (tester) async {
    await pumpHarness(tester);
    await showAppOverviewDialog(
      tester.element(find.byType(Scaffold)),
      firstRun: true,
      isSuppressedOverride: (_) => true,
    );
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('manual open always shows, even when suppressed', (tester) async {
    await pumpHarness(tester);
    final future = showAppOverviewDialog(
      tester.element(find.byType(Scaffold)),
      isSuppressedOverride: (_) => true,
    );
    await tester.pump();

    expect(find.text('What makes IRIS different'), findsOneWidget);
    // The explicit request carries no suppression box.
    expect(find.byType(CheckboxListTile), findsNothing);
    await tester.tap(find.text('OK'));
    await tester.pump();
    await future;
  });
}
