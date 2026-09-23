import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/virtual_media/model/domain/vm_rule.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/db/migration/v36_migration.dart';

import 'helpers/sqlite3_loader.dart';

/// Schema v36 contract: `vm_rules` gains the per-file exclusion switches
/// (`use_exclude_overlong`, `max_single_duration_minutes`,
/// `skip_single_segment`) and the repository round-trips/clamps them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqlite3Loaded();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  late AppDatabase db;

  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory());
    await DbModule.init(db);
  });

  tearDownAll(() async {
    await db.close();
  });

  Future<Set<String>> vmRuleColumns() async {
    final rows =
        await db.customSelect('PRAGMA table_info(vm_rules)').get();
    return rows.map((row) => row.read<String>('name')).toSet();
  }

  test('schemaVersion advanced to 36', () {
    expect(db.schemaVersion, greaterThanOrEqualTo(36));
  });

  test('vm_rules carries the exclusion columns', () async {
    final cols = await vmRuleColumns();
    expect(
        cols,
        containsAll([
          'use_exclude_overlong',
          'max_single_duration_minutes',
          'skip_single_segment',
        ]));
  });

  test('MigrationV36 is re-entrant (no-op when columns exist)', () async {
    await MigrationV36(db).run(db.createMigrator());
    final cols = await vmRuleColumns();
    expect(
        cols,
        containsAll([
          'use_exclude_overlong',
          'max_single_duration_minutes',
          'skip_single_segment',
        ]));
  });

  test('a row inserted without the new columns reads the defaults', () async {
    await db.customInsert(
      'INSERT INTO vm_rules (id, name) VALUES (?, ?)',
      variables: [
        Variable.withString('vw_defaults'),
        Variable.withString('defaults'),
      ],
    );
    final rule = await DbModule.virtualMediaRepo.ruleById('vw_defaults');
    expect(rule, isNotNull);
    expect(rule!.useExcludeOverlong, isTrue);
    expect(rule.maxSingleDurationMinutes, kVmDefaultMaxSingleDurationMinutes);
    expect(rule.skipSingleSegment, isTrue);
  });

  test('repository round-trips the switches and clamps the threshold',
      () async {
    await DbModule.virtualMediaRepo.saveRule(VirtualMediaRule(
      id: 'vw_roundtrip',
      name: 'roundtrip',
      useExcludeOverlong: false,
      maxSingleDurationMinutes: 999, // dirty → clamp to the hard ceiling
      skipSingleSegment: false,
    ));
    final rule = await DbModule.virtualMediaRepo.ruleById('vw_roundtrip');
    expect(rule, isNotNull);
    expect(rule!.useExcludeOverlong, isFalse);
    expect(rule.maxSingleDurationMinutes, kVmHardMaxDurationMinutes);
    expect(rule.skipSingleSegment, isFalse);
  });
}
