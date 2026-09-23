import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:iris/features/scenario_playback/actions/scenario_playback_actions.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/warning_dialogs.dart';
import 'package:zustand/zustand.dart';

import 'helpers/sqlite3_loader.dart';

class _TestStoreScope extends SingleChildStatefulWidget {
  const _TestStoreScope({required Widget child}) : super(child: child);
  @override
  State<_TestStoreScope> createState() => _TestStoreScopeState();
}

class _TestStoreScopeState extends SingleChildState<_TestStoreScope> {
  @override
  Widget buildWithChild(BuildContext context, Widget? child) {
    return InheritedProvider<StoreLocator>.value(
      value: StoreLocator(),
      startListening: (e, v) {
        final sub = v.changes.listen((_) => e.markNeedsNotifyDependents());
        return sub.cancel;
      },
      child: child,
    );
  }
}

/// The first folder/selection play must explain the workspace-override model
/// once, with the "don't show again" box ticked by default.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqlite3Loaded();

  setUpAll(() async {
    final db = AppDatabase(NativeDatabase.memory());
    await DbModule.init(db);
  });

  setUp(() async {
    final s = useAppStore();
    if (s.state.suppressedWarnings.isNotEmpty) {
      await s.resetSuppressedWarnings();
    }
  });

  Future<void> pumpTrigger(
    WidgetTester tester, {
    required void Function(BuildContext context) onRun,
  }) async {
    await tester.pumpWidget(_TestStoreScope(
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => onRun(context),
                child: const Text('run'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('first play shows the checked notice and suppresses on OK',
      (tester) async {
    var ran = false;
    await pumpTrigger(tester, onRun: (context) {
      ScenarioPlaybackActions.runPlayActionWithNoMediaConfirm(
        context,
        action: ({bool force = false}) async {
          ran = true;
        },
      );
    });

    await tester.tap(find.text('run'));
    await tester.pumpAndSettle();

    expect(find.text('Workspace replaced on play'), findsOneWidget);
    final checkbox = find.byType(CheckboxListTile);
    expect(tester.widget<CheckboxListTile>(checkbox).value, isTrue);
    // The explainer precedes the action.
    expect(ran, isFalse);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    expect(ran, isTrue);
    expect(useAppStore().state.suppressedWarnings,
        contains(kWarningScenarioWorkspace));
  });

  testWidgets('cancelling the notice aborts the play and keeps it showing',
      (tester) async {
    var ran = false;
    await pumpTrigger(tester, onRun: (context) {
      ScenarioPlaybackActions.runPlayActionWithNoMediaConfirm(
        context,
        action: ({bool force = false}) async {
          ran = true;
        },
      );
    });

    await tester.tap(find.text('run'));
    await tester.pumpAndSettle();

    expect(find.text('Workspace replaced on play'), findsOneWidget);
    // The notice precedes a write to the playing workspace, so it must offer a
    // real cancel — not just an acknowledgement.
    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    expect(ran, isFalse);
    // Cancelling is not the same as "don't show again": the notice survives.
    expect(useAppStore().state.suppressedWarnings,
        isNot(contains(kWarningScenarioWorkspace)));
  });

  testWidgets('a suppressed notice runs the action without any dialog',
      (tester) async {
    await tester.runAsync(
        () => useAppStore().suppressWarning(kWarningScenarioWorkspace));
    var ran = false;
    await pumpTrigger(tester, onRun: (context) {
      ScenarioPlaybackActions.runPlayActionWithNoMediaConfirm(
        context,
        action: ({bool force = false}) async {
          ran = true;
        },
      );
    });

    await tester.tap(find.text('run'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(ran, isTrue);
  });
}
