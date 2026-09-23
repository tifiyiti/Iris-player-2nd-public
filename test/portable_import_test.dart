import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/store/kv/kv_keys.dart';
import 'package:iris/store/kv/secure_kv.dart';
import 'package:iris/utils/portable_import.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('iris_portable_import');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('shouldOfferPortableImport', () {
    test('offers exactly once when there is something to import', () {
      expect(
        shouldOfferPortableImport(alreadyDecided: false, anythingToImport: true),
        isTrue,
      );
      expect(
        shouldOfferPortableImport(alreadyDecided: true, anythingToImport: true),
        isFalse,
      );
      expect(
        shouldOfferPortableImport(
            alreadyDecided: false, anythingToImport: false),
        isFalse,
      );
      expect(
        shouldOfferPortableImport(alreadyDecided: true, anythingToImport: false),
        isFalse,
      );
    });
  });

  group('scanPortableImportSources', () {
    test('detects legacy db file and counts non-secret kv entries',
        () async {
      final legacyDb = File(p.join(tempDir.path, 'old_storages.db'));
      await legacyDb.writeAsBytes([1, 2, 3]);

      final legacyKv = MemoryKvStore()
        ..values[KvKeys.appState] = '{}'
        ..values[KvKeys.historyState] = '[]'
        // Secrets must never be counted as migratable.
        ..values[KvKeys.storageState] = 'creds';

      final scan = await scanPortableImportSources(
        legacyDbFilePath: legacyDb.path,
        legacyKv: legacyKv,
      );

      expect(scan.legacyDbExists, isTrue);
      expect(scan.migratableKvCount, 2);
      expect(scan.anything, isTrue);
    });

    test('nothing present yields a negative scan', () async {
      final scan = await scanPortableImportSources(
        legacyDbFilePath: p.join(tempDir.path, 'missing.db'),
        legacyKv: MemoryKvStore(),
      );

      expect(scan.legacyDbExists, isFalse);
      expect(scan.migratableKvCount, 0);
      expect(scan.anything, isFalse);
    });
  });

  group('performPortableImport', () {
    test('copies db (with wal/shm siblings) into the portable target',
        () async {
      final legacyDb = File(p.join(tempDir.path, 'old_storages.db'));
      await legacyDb.writeAsBytes([9, 9]);
      await File('${legacyDb.path}-wal').writeAsBytes([7]);
      await File('${legacyDb.path}-shm').writeAsBytes([8]);

      final targetDir = p.join(tempDir.path, 'userdata', 'db');
      final targetDb =
          File(p.join(targetDir, 'iris_storages.db'));

      final legacyKv = MemoryKvStore();
      final targetKv = MemoryKvStore();

      final outcome = await performPortableImport(
        legacyDbFilePath: legacyDb.path,
        targetDbFilePath: targetDb.path,
        legacyKv: legacyKv,
        targetKv: targetKv,
      );

      expect(outcome.dbCopied, isTrue);
      expect(targetDb.readAsBytesSync(), [9, 9]);
      expect(File('${targetDb.path}-wal').readAsBytesSync(), [7]);
      expect(File('${targetDb.path}-shm').readAsBytesSync(), [8]);
      expect(await targetKv.containsKey(key: KvKeys.internalImportDone),
          isTrue);
    });

    test('migrates non-secret keys only and skips absent ones', () async {
      final legacyKv = MemoryKvStore()
        ..values[KvKeys.appState] = '{"theme":"dark"}'
        ..values[KvKeys.mediaLibSelection] = '{"a":1}'
        ..values[KvKeys.storageState] = 'creds'
        ..values['unknown_legacy_key'] = 'ignored';

      final targetKv = MemoryKvStore();

      final outcome = await performPortableImport(
        legacyDbFilePath: p.join(tempDir.path, 'missing.db'),
        targetDbFilePath: p.join(tempDir.path, 'userdata', 'db', 'x.db'),
        legacyKv: legacyKv,
        targetKv: targetKv,
      );

      expect(outcome.dbCopied, isFalse);
      expect(outcome.kvMigrated, 2);
      expect(await targetKv.read(key: KvKeys.appState), '{"theme":"dark"}');
      expect(
          await targetKv.read(key: KvKeys.mediaLibSelection), '{"a":1}');
      expect(
        await targetKv.containsKey(key: KvKeys.storageState),
        isFalse,
        reason: 'credential-bearing keys must stay machine-bound',
      );
      expect(
        await targetKv.containsKey(key: 'unknown_legacy_key'),
        isFalse,
        reason: 'only curated KvKeys.all keys migrate',
      );
    });

    test('markPortableImportSkipped records the decision', () async {
      final targetKv = MemoryKvStore();
      await markPortableImportSkipped(targetKv);
      expect(
        await targetKv.containsKey(key: KvKeys.internalImportSkipped),
        isTrue,
      );
    });
  });
}
