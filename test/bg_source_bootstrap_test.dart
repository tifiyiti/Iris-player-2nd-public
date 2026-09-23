import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/model/db/dao/bg_source_rules_dao.dart';
import 'package:iris/features/background_playback/model/db/repositories/bg_source_rule_repository.dart';
import 'package:iris/features/background_playback/store/bg_source_bootstrap.dart';
import 'package:iris/models/db/app_database.dart';

import 'helpers/sqlite3_loader.dart';

void main() {
  ensureSqlite3Loaded();

  late AppDatabase db;
  late BgSourceRuleRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = BgSourceRuleRepository(rulesDao: BgSourceRulesDao(db));
    BgSourceBootstrap.resetForTests();
  });

  tearDown(() => db.close());

  test('seeds exactly one built-in rule, idempotently', () async {
    await BgSourceBootstrap.ensure(repo);
    // Re-run WITHOUT the latch: the fixed id must not duplicate.
    BgSourceBootstrap.resetForTests();
    await BgSourceBootstrap.ensure(repo);

    final builtin = (await repo.loadRules())
        .where((r) => r.id == BgSourceBootstrap.builtinRuleId)
        .toList();
    expect(builtin, hasLength(1));
    expect(builtin.single.builtin, isTrue);
    expect(builtin.single.enabled, isTrue);
    expect(builtin.single.pinned, isTrue);
  });

  test('the seeded built-in rule survives deleteRule', () async {
    await BgSourceBootstrap.ensure(repo);
    await repo.deleteRule(BgSourceBootstrap.builtinRuleId);
    expect(await repo.ruleById(BgSourceBootstrap.builtinRuleId), isNotNull);
  });
}
