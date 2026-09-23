import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/model/db/dao/bg_source_rules_dao.dart';
import 'package:iris/features/background_playback/model/db/repositories/bg_source_rule_repository.dart';
import 'package:iris/features/background_playback/model/enum/bg_source_rule_kind.dart';
import 'package:iris/features/background_playback/model/source/bg_source_rule.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/dir_match.dart';

import 'helpers/sqlite3_loader.dart';

void main() {
  ensureSqlite3Loaded();

  late AppDatabase db;
  late BgSourceRuleRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = BgSourceRuleRepository(rulesDao: BgSourceRulesDao(db));
  });

  tearDown(() => db.close());

  test('orders pinned-first then insertion order', () async {
    await repo.saveRule(const BgSourceRule(id: 'a', sortOrder: 1));
    await repo.saveRule(const BgSourceRule(id: 'b', sortOrder: 0));
    await repo.saveRule(const BgSourceRule(id: 'c', sortOrder: 5, pinned: true));

    final rules = await repo.loadRules();
    expect(rules.map((r) => r.id).toList(), ['c', 'b', 'a']);
  });

  test('round-trips directory config and patterns', () async {
    await repo.saveRule(const BgSourceRule(
      id: 'dir',
      kind: BgSourceRuleKind.directory,
      matchMode: DirMatchMode.patternDirRecursive,
      paths: ['Anime'],
      patterns: [
        DirPatternEntry(kind: DirPatternKind.suffix, text: 'S1'),
      ],
      tagFilterEnabled: true,
      filterTagId: 7,
    ));

    final rule = (await repo.loadRules()).single;
    expect(rule.kind, BgSourceRuleKind.directory);
    expect(rule.matchMode, DirMatchMode.patternDirRecursive);
    expect(rule.paths, ['Anime']);
    expect(rule.patterns.single.text, 'S1');
    expect(rule.tagFilterEnabled, isTrue);
    expect(rule.filterTagId, 7);
  });

  test('nextSortOrder appends after the current maximum', () async {
    expect(await repo.nextSortOrder(), 0);
    await repo.saveRule(const BgSourceRule(id: 'a', sortOrder: 0));
    await repo.saveRule(const BgSourceRule(id: 'b', sortOrder: 3));
    expect(await repo.nextSortOrder(), 4);
  });

  test('the built-in rule cannot be deleted', () async {
    await repo.saveRule(const BgSourceRule(id: 'builtin', builtin: true));
    await repo.deleteRule('builtin');
    expect(await repo.ruleById('builtin'), isNotNull);

    await repo.saveRule(const BgSourceRule(id: 'normal'));
    await repo.deleteRule('normal');
    expect(await repo.ruleById('normal'), isNull);
  });
}
