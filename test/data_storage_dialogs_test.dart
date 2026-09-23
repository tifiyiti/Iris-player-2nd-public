import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/utils/portable_import.dart';
import 'package:iris/widgets/dialogs/show_data_storage_info_dialog.dart';
import 'package:iris/widgets/dialogs/show_portable_import_dialog.dart';

/// Pumps a minimal host page whose single button opens the dialog under
/// test; both dialogs are plain [showDialog] wrappers without plugin
/// dependencies, so no mocks are needed.
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
  group('storageInfoSections (pure)', () {
    testWidgets('windows layout covers portable layout and the escape hatch',
        (tester) async {
      late List<StorageInfoSection> sections;
      await _pumpDialogOpener(tester, (ctx) async {
        sections = storageInfoSections(
            windows: true, t: AppLocalizations.of(ctx)!);
      });
      final text = sections.map((s) => '${s.header}\n${s.body}').join('\n');

      expect(text, contains('userdata'));
      expect(text, contains('IRIS_NO_PORTABLE'));
      expect(text, isNot(contains('app-private')));
    });

    testWidgets('generic layout covers app-private storage without Windows terms',
        (tester) async {
      late List<StorageInfoSection> sections;
      await _pumpDialogOpener(tester, (ctx) async {
        sections = storageInfoSections(
            windows: false, t: AppLocalizations.of(ctx)!);
      });
      final text = sections.map((s) => '${s.header}\n${s.body}').join('\n');

      expect(text, contains('app-private'));
      expect(text, contains('uninstall')); // uninstall wipes app-private data
      expect(
          text, contains('re-enter')); // credentials re-entered on new device
      expect(text, contains('plaintext')); // plaintext risk still disclosed
      // Windows-only concepts must not leak into the generic branch.
      expect(text, isNot(contains('IRIS_NO_PORTABLE')));
      expect(text, isNot(contains('userdata')));
    });
  });

  group('DataStorageInfoDialog', () {
    testWidgets('explains portable layout, migration and the escape hatch',
        (tester) async {
      await _pumpDialogOpener(tester, showDataStorageInfoDialog);

      expect(find.textContaining('userdata'), findsWidgets);
      expect(find.textContaining('IRIS_NO_PORTABLE'), findsOneWidget);
    });

    testWidgets('warns about machine-bound credentials and plaintext risk',
        (tester) async {
      await _pumpDialogOpener(tester, showDataStorageInfoDialog);

      // Passwords do NOT travel with the folder...
      expect(find.textContaining('re-enter'), findsWidgets);
      // ...and meta-era credentials are stored in plaintext inside the DB.
      expect(find.textContaining('plaintext'), findsWidgets);
    });

    testWidgets('renders the generic layout when forced off-Windows',
        (tester) async {
      await _pumpDialogOpener(
          tester, (ctx) => showDataStorageInfoDialog(ctx, windows: false));

      expect(find.textContaining('app-private'), findsWidgets);
      expect(find.textContaining('IRIS_NO_PORTABLE'), findsNothing);
      expect(find.textContaining('userdata'), findsNothing);
    });
  });

  group('PortableImportDialog', () {
    testWidgets('keeps listing found data and explains password caveats',
        (tester) async {
      const scan =
          PortableImportScanResult(legacyDbExists: true, migratableKvCount: 2);
      await _pumpDialogOpener(tester, (ctx) async {
        await showPortableImportDialog(ctx, scan: scan);
      });

      // Found-data lines are still shown.
      expect(find.textContaining('Media library database'), findsOneWidget);
      expect(find.textContaining('2 UI settings'), findsOneWidget);
      // Expanded caveat: machine-bound passwords + plaintext warning +
      // legacy data stays untouched.
      expect(find.textContaining('passwords', findRichText: true),
          findsWidgets);
      expect(find.textContaining('plaintext'), findsWidgets);
      expect(find.textContaining('left untouched'), findsOneWidget);
    });
  });
}
