import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/virtual_media/model/domain/vm_rule.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';

import 'helpers/sqlite3_loader.dart';

VirtualMediaRule _rule(String id) => VirtualMediaRule(
      id: id,
      name: 'rule $id',
    );

/// Deleting a rule must not leave stray rows: `deleteRuleCascade` removes the
/// rule plus its per-scenario progress and resume anchors (the sheet and
/// the manager page share these semantics for the same object).
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

  test('v33 vm_progress indexes exist (no full-scan deletes)', () async {
    for (final name in [
      'idx_vm_progress_scope_key',
      'idx_vm_progress_rule',
    ]) {
      final rows = await db.customSelect(
        'SELECT name FROM sqlite_master WHERE type = ? AND name = ?',
        variables: [
          Variable.withString('index'),
          Variable.withString(name),
        ],
      ).get();
      expect(rows.map((r) => r.read<String>('name')), contains(name));
    }
  });

  test('deleteRuleCascade removes rule, progress and anchors', () async {
    final repo = DbModule.virtualMediaRepo;
    const ruleId = 'vm_cascade_probe';
    const scopeKey = 'vm_cascade_probe|dir|#1';

    await repo.saveRule(_rule(ruleId));
    await repo.saveVmProgress(
      scenarioId: 'sys',
      tagId: '',
      ruleId: ruleId,
      scopeKey: scopeKey,
      segmentKey: 'st1:a.mp4',
      localPositionMs: 123,
    );
    await repo.saveAnchor(
      scopeKey: scopeKey,
      segmentKey: 'st1:a.mp4',
      localPositionMs: 123,
    );

    await repo.deleteRuleCascade(ruleId);

    expect(await repo.ruleById(ruleId), isNull);
    expect(await repo.loadAnchor(scopeKey), isNull);
    final progress = await repo.progressDao
        .get('sys', '', scopeKey);
    expect(progress, isNull);
  });
}
