import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/model/enum/bg_source_rule_kind.dart';
import 'package:iris/features/background_playback/view/bg_source_rule_editor.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/utils/dir_match.dart';

import 'helpers/sqlite3_loader.dart';

// The media-browser "Add as audio source" quick-add builds folder-scoped
// defaults (storage+folder name, recursive specified dir) and the editor
// prefills from them.
void main() {
  ensureSqlite3Loaded();

  const channel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  late AppDatabase moduleDb;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    moduleDb = AppDatabase(NativeDatabase.memory());
    await DbModule.init(moduleDb);
  });
  tearDownAll(() => moduleDb.close());

  group('folderSourceRuleDefaults', () {
    test('names storage + folder and picks recursive specified dir', () {
      final d = folderSourceRuleDefaults(
        storageName: 'E',
        folderName: 'Anime',
        folderPath: 'Anime',
      );
      expect(d.name, 'E - Anime');
      expect(d.matchMode, DirMatchMode.specifiedDirRecursive);
      expect(d.paths, ['Anime']);
      expect(d.description, isNotEmpty);
    });

    test('a storage root falls back to the storage name', () {
      final d = folderSourceRuleDefaults(
        storageName: 'E',
        folderName: '',
        folderPath: '',
      );
      expect(d.name, 'E');
      expect(d.paths, ['']);
    });
  });

  testWidgets('editor prefills a folder draft', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(
        body: BgSourceRuleEditorDialog(
          sortOrder: 0,
          defaultKind: BgSourceRuleKind.directory,
          defaultMatchMode: DirMatchMode.specifiedDirRecursive,
          defaultPaths: ['Anime'],
          defaultName: 'E - Anime',
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('E - Anime'), findsOneWidget);
    expect(find.text('Anime'), findsOneWidget);
    expect(find.text('指定目录（递归）'), findsOneWidget);
  });
}
