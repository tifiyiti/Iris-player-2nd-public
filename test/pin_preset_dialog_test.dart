import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/tag_play/model/domain/tag_play_pin_preset.dart';
import 'package:iris/features/tag_play/view/dialogs/show_pin_preset_dialog.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';

import 'helpers/sqlite3_loader.dart';

/// The preset-name field must keep its controller (and therefore the user's
/// typed text) across the dialog's rebuilds. The async `presets()` load — and
/// every save/delete refresh — used to rebuild the form with a freshly
/// allocated `TextEditingController`, which wiped the field and leaked the old
/// controller.
void main() {
  ensureSqlite3Loaded();
  TestWidgetsFlutterBinding.ensureInitialized();

  // `DbModule`'s fields are `late final`, so the in-memory DB is wired once for
  // the whole file; each test starts from an empty preset table instead.
  setUpAll(() async {
    await DbModule.init(AppDatabase(NativeDatabase.memory()));
  });

  setUp(() async {
    for (final preset in await DbModule.tagPlayRepo.presets()) {
      await DbModule.tagPlayRepo.deletePreset(preset.id);
    }
  });

  Widget tree() {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showPinPresetDialog(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(tree());
    // Deferred localizations must settle before the app shell builds.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('open'));
    await tester.pump();
  }

  /// Lets a pending drift future land and the resulting rebuild paint.
  Future<void> pumpRefresh(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> seedPreset(String name) =>
      DbModule.tagPlayRepo.savePreset(TagPlayPinPreset(
        id: 0,
        name: name,
        pinnedTagIds: const [1, 2],
      ));

  testWidgets('typed name survives the async presets load', (tester) async {
    await seedPreset('扫盘套装');

    await openDialog(tester);

    // First frame: the list query has not landed yet.
    expect(find.text('No saved presets'), findsOneWidget);
    final field = find.byType(TextField);
    final ctrl = tester.widget<TextField>(field).controller!;

    await tester.enterText(field, 'my preset');
    await tester.pump();

    await pumpRefresh(tester);

    // The seeded preset proves the load landed and rebuilt the dialog.
    expect(find.text('扫盘套装'), findsOneWidget);
    expect(find.text('No saved presets'), findsNothing);
    // ...and the field kept its controller and its text.
    expect(identical(tester.widget<TextField>(field).controller, ctrl), isTrue);
    expect(ctrl.text, 'my preset');
    expect(find.text('my preset'), findsOneWidget);
  });

  testWidgets('typed name survives the delete-triggered refresh',
      (tester) async {
    await seedPreset('扫盘套装');

    await openDialog(tester);
    await pumpRefresh(tester);
    expect(find.text('扫盘套装'), findsOneWidget);

    final field = find.byType(TextField);
    final ctrl = tester.widget<TextField>(field).controller!;
    await tester.enterText(field, 'my preset');
    await tester.pump();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await pumpRefresh(tester);

    // Deleting refreshes the list...
    expect(find.text('扫盘套装'), findsNothing);
    expect(find.text('No saved presets'), findsOneWidget);
    // ...without disturbing the name being typed.
    expect(identical(tester.widget<TextField>(field).controller, ctrl), isTrue);
    expect(ctrl.text, 'my preset');
    expect(find.text('my preset'), findsOneWidget);
  });
}
