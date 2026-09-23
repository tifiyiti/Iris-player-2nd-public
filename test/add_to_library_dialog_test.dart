import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/services/show_add_to_library_dialog.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';

/// The "no libraries" branch of [showAddToLibraryDialog] must be
/// dismissable: its OK button was once left with `onPressed: null`
/// (permanently disabled), trapping the user with no way to close it
/// except the system back button.
void main() {
  late AppDatabase db;

  setUpAll(() {
    db = AppDatabase(NativeDatabase.memory());
    DbModule.init(db);
  });

  tearDownAll(() async {
    await db.close();
  });

  Widget tree(Future<String?> Function(BuildContext) show) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => show(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
  }

  testWidgets('no-libraries dialog is dismissable via OK', (tester) async {
    String? result = 'sentinel';
    await tester.pumpWidget(tree((context) async {
      result = await showAddToLibraryDialog(context);
      return result;
    }));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Fresh in-memory DB holds no user libraries.
    expect(find.text('No Libraries'), findsOneWidget);
    expect(find.text('Create a library first.'), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('No Libraries'), findsNothing);
    expect(result, isNull);
  });
}
