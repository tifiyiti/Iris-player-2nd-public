import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/model/db/repositories/bg_source_rule_repository.dart';
import 'package:iris/features/background_playback/model/enum/bg_source_rule_kind.dart';
import 'package:iris/features/background_playback/model/source/bg_source_rule.dart';
import 'package:iris/features/background_playback/view/bg_source_manage_page.dart';
import 'package:iris/features/background_playback/view/bg_source_rule_editor.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';

import 'helpers/sqlite3_loader.dart';

void main() {
  ensureSqlite3Loaded();
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  late AppDatabase moduleDb;
  setUpAll(() async {
    moduleDb = AppDatabase(NativeDatabase.memory());
    await DbModule.init(moduleDb);
  });
  tearDownAll(() => moduleDb.close());

  setUp(() async {
    for (final r in await DbModule.bgSourceRuleRepo.loadRules()) {
      await DbModule.bgSourceRuleRepo.deleteRule(r.id);
    }
  });

  Future<void> pumpManage(WidgetTester tester,
      {BgSourceRuleRepository? repo}) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => Dialog(
                  child: SizedBox(
                    width: 420,
                    height: 520,
                    child: BgSourceManageBody(repo: repo),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a load failure shows an error with a working retry',
      (tester) async {
    await DbModule.bgSourceRuleRepo
        .saveRule(const BgSourceRule(id: 'r', sortOrder: 0));
    final repo = _FlakyRepo(
      rulesDao: DbModule.bgSourceRuleRepo.rulesDao,
      loadFailures: 1,
    );

    await pumpManage(tester, repo: repo);
    // The failure surfaces as an error body, never an endless spinner.
    expect(find.text('Could not load Sub Audio sources.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // Retry re-runs the load against the now-healthy repo.
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsOneWidget);
    expect(find.text('Could not load Sub Audio sources.'), findsNothing);
  });

  testWidgets('a failed confirm shows an error and keeps the manager open',
      (tester) async {
    await DbModule.bgSourceRuleRepo
        .saveRule(const BgSourceRule(id: 'c', sortOrder: 0));
    final repo = _SaveFailRepo(rulesDao: DbModule.bgSourceRuleRepo.rulesDao);

    await pumpManage(tester, repo: repo);
    expect(find.byType(ListTile), findsOneWidget);

    // Stage a change, then confirm — the save throws.
    await tester.tap(find.byType(ListTile));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.check_rounded));
    await tester.pumpAndSettle();

    expect(find.textContaining('could not be saved'), findsOneWidget);
    // The manager stays open so the user can retry or discard.
    expect(find.byType(BgSourceManageBody), findsOneWidget);
  });

  testWidgets('a staged enable toggle is not written until confirm',
      (tester) async {
    await DbModule.bgSourceRuleRepo
        .saveRule(const BgSourceRule(id: 'a', sortOrder: 0));

    await pumpManage(tester);
    expect(find.byType(ListTile), findsOneWidget);

    // Toggle the enable radio: only the working copy changes.
    await tester.tap(find.byType(ListTile));
    await tester.pump();
    expect((await DbModule.bgSourceRuleRepo.ruleById('a'))!.enabled, isTrue);

    // Confirm applies the staged edit.
    await tester.tap(find.byIcon(Icons.check_rounded));
    await tester.pumpAndSettle();
    expect((await DbModule.bgSourceRuleRepo.ruleById('a'))!.enabled, isFalse);
  });

  testWidgets('discard leaves the DB untouched', (tester) async {
    await DbModule.bgSourceRuleRepo
        .saveRule(const BgSourceRule(id: 'b', sortOrder: 0));

    await pumpManage(tester);
    await tester.tap(find.byType(ListTile));
    await tester.pump();

    // The only TextButton in the body is Discard.
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    expect((await DbModule.bgSourceRuleRepo.ruleById('b'))!.enabled, isTrue);
  });

  Future<BgSourceRule?> openEditor(
    WidgetTester tester, {
    required bool persist,
  }) async {
    BgSourceRule? result;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await openBgSourceRuleEditor(
                  context,
                  initial: const BgSourceRule(
                    id: 'x',
                    kind: BgSourceRuleKind.directory,
                    paths: ['Anime'],
                  ),
                  sortOrder: 0,
                  persist: persist,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('persist:false returns the rule without writing', (tester) async {
    final result = await openEditor(tester, persist: false);
    expect(result?.id, 'x');
    expect(await DbModule.bgSourceRuleRepo.ruleById('x'), isNull);
  });

  testWidgets('persist:true writes before returning', (tester) async {
    final result = await openEditor(tester, persist: true);
    expect(result?.id, 'x');
    expect(await DbModule.bgSourceRuleRepo.ruleById('x'), isNotNull);
  });
}

/// Fails the first [loadFailures] loads, then delegates to the real repo.
class _FlakyRepo extends BgSourceRuleRepository {
  _FlakyRepo({required super.rulesDao, required this.loadFailures});

  int loadFailures;

  @override
  Future<List<BgSourceRule>> loadRules() {
    if (loadFailures > 0) {
      loadFailures--;
      return Future.error(Exception('load boom'));
    }
    return super.loadRules();
  }
}

/// Always throws on save, so the confirm error path is exercised.
class _SaveFailRepo extends BgSourceRuleRepository {
  _SaveFailRepo({required super.rulesDao});

  @override
  Future<void> saveRule(BgSourceRule rule) =>
      Future.error(Exception('save boom'));
}
