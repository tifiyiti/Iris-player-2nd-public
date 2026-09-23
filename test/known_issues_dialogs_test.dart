import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/widgets/dialogs/show_known_issues_dialog.dart';

/// Pumps a minimal host page whose single button opens the dialog under test.
/// The dialog is a plain [showDialog] wrapper without plugin dependencies, so
/// no mocks are needed.
Future<void> _pumpDialogOpener(
  WidgetTester tester,
  Future<dynamic> Function(BuildContext) open,
) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => open(context),
            child: const Text('OPEN'),
          ),
        ),
      ),
    ),
  ));
  // Deferred l10n delegates load async — settle once before tapping.
  await tester.pumpAndSettle();
  await tester.tap(find.text('OPEN'));
  await tester.pumpAndSettle();
}

void main() {
  group('knownIssueSections (pure)', () {
    testWidgets('Windows: includes fullscreen, thread-mode and media_kit entries',
        (tester) async {
      late List<KnownIssueSection> sections;
      await _pumpDialogOpener(tester, (ctx) async {
        sections =
            knownIssueSections(windows: true, t: AppLocalizations.of(ctx)!);
      });
      final text = sections.map((s) => '${s.header}\n${s.body}').join('\n');

      expect(text, contains('window_manager native defect'));
      expect(text, contains('Flutter 3.35+'));
      expect(text, contains('media-kit #1324'));
      expect(text, contains('5,000'));
      expect(text, contains('entire merged item unplayable'));
      // The optimisation note that follows the VM-merge entry.
      expect(text, contains('shared derived index'));
      expect(text, contains('bitmap'));
      // The multi-select gate note applies on every platform.
      expect(text, contains('does not take part in multi-select'));
    });

    testWidgets('non-Windows: only the cross-platform entries',
        (tester) async {
      late List<KnownIssueSection> sections;
      await _pumpDialogOpener(tester, (ctx) async {
        sections =
            knownIssueSections(windows: false, t: AppLocalizations.of(ctx)!);
      });
      final text = sections.map((s) => '${s.header}\n${s.body}').join('\n');

      expect(text, contains('media-kit #1324'));
      expect(text, contains('5,000'));
      // The optimisation note is cross-platform (like the entry it follows).
      expect(text, contains('shared derived index'));
      // The multi-select gate note is cross-platform as well.
      expect(text, contains('does not take part in multi-select'));
      // Windows-only entries must not leak into the generic branch.
      expect(text, isNot(contains('window_manager native defect')));
      expect(text, isNot(contains('Flutter 3.35+')));
      expect(text, isNot(contains('entire merged item unplayable')));
    });
  });

  group('KnownIssuesDialog', () {
    testWidgets('opens with title and lists the Windows entries',
        (tester) async {
      await _pumpDialogOpener(
          tester, (ctx) => showKnownIssuesDialog(ctx, windows: true));

      expect(find.text('Known issues'), findsWidgets);
      expect(find.textContaining('window_manager native defect'), findsOneWidget);
      expect(find.textContaining('media-kit #1324'), findsOneWidget);
      expect(find.text('Got it'), findsOneWidget);
    });

    testWidgets('renders the generic layout when forced off-Windows',
        (tester) async {
      await _pumpDialogOpener(
          tester, (ctx) => showKnownIssuesDialog(ctx, windows: false));

      expect(find.textContaining('media-kit #1324'), findsOneWidget);
      expect(find.textContaining('window_manager native defect'), findsNothing);
    });
  });
}
