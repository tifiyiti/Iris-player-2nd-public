import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/db/security/storage_cipher.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/widgets/dialogs/show_storage_password_locked_dialog.dart';

import 'helpers/sqlite3_loader.dart';

Future<void> _seedLockedWebdavRow(String id, String name) {
  return DbModule.storageDao.insert(
    StoragesTableCompanion.insert(
      id: id,
      type: StorageType.webdav.index,
      name: name,
      basePath: '["/"]',
      host: const Value('192.168.1.4'),
      port: const Value('8090'),
      username: const Value('u'),
      password: const Value(null),
      passwordCipher: Value(base64Encode(List<int>.generate(32, (i) => i))),
      passwordNonce: Value(base64Encode(List<int>.generate(12, (i) => i))),
      https: const Value(false),
    ),
  );
}

void main() {
  ensureSqlite3Loaded();
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  setUpAll(() async {
    await DbModule.init(AppDatabase(NativeDatabase.memory()));
  });

  setUp(() async {
    StorageCipher.resetForTest();
    debugResetStoragePasswordLockedNotice();
    for (final row in await DbModule.storageDao.getAll()) {
      await DbModule.storageDao.deleteById(row.id);
    }
  });

  Widget tree() {
    return StoreScope(
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showStoragePasswordLockedDialogIfNeeded(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('lists the affected entries and shows at most once',
      (tester) async {
    await _seedLockedWebdavRow('s1', 'home-nas');
    // Populate the repository's locked set the same way startup does.
    await DbModule.storageRepo.getStorages();

    await tester.pumpWidget(tree());
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Storage password unavailable'), findsOneWidget);
    expect(find.textContaining('home-nas'), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // One-shot per process: a second call is a no-op.
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Storage password unavailable'), findsNothing);
  });

  testWidgets('stays silent when every row decrypted cleanly', (tester) async {
    await DbModule.storageRepo.getStorages();

    await tester.pumpWidget(tree());
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Storage password unavailable'), findsNothing);
  });
}
