import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/pages/bootstrap_gate.dart';

/// Regression: `completeStartupInitialization` used to run outside any
/// try/catch. Any throw (corrupt DB, failed migration, plugin registration)
/// left the gate on an unresolvable spinner with no way forward. A failure
/// must surface a recoverable screen, and Retry must re-run the sequence.
Future<void> pumpGate(
  WidgetTester tester, {
  required Future<void> Function() initialize,
}) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: BootstrapGate(
      initialize: initialize,
      child: const Scaffold(body: Text('APP READY')),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a failing startup shows a recoverable error, then succeeds on retry',
      (tester) async {
    var attempts = 0;
    await pumpGate(tester, initialize: () async {
      attempts++;
      if (attempts < 2) throw StateError('boom');
    });

    expect(find.text('Startup failed'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('APP READY'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('APP READY'), findsOneWidget);
    expect(find.text('Startup failed'), findsNothing);
  });

  testWidgets('a successful startup renders the app without an error screen',
      (tester) async {
    await pumpGate(tester, initialize: () async {});
    expect(find.text('APP READY'), findsOneWidget);
    expect(find.text('Startup failed'), findsNothing);
  });
}
