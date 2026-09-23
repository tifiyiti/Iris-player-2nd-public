import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/model/enum/bg_source_rule_kind.dart';
import 'package:iris/features/background_playback/model/source/bg_source_rule.dart';
import 'package:iris/features/background_playback/view/bg_source_rule_editor.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/utils/dir_match.dart';

import 'helpers/sqlite3_loader.dart';

BgSourceRule _dirRule() => const BgSourceRule(
      id: 'dir',
      kind: BgSourceRuleKind.directory,
      matchMode: DirMatchMode.patternDir,
      paths: ['Anime'],
      patterns: [
        DirPatternEntry(kind: DirPatternKind.suffix, text: 'S1'),
      ],
    );

void main() {
  ensureSqlite3Loaded();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  late AppDatabase moduleDb;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async => null);
    moduleDb = AppDatabase(NativeDatabase.memory());
    await DbModule.init(moduleDb);
  });
  tearDownAll(() => moduleDb.close());

  Future<void> pumpEditor(
    WidgetTester tester, {
    required Widget child,
    Size surface = const Size(360, 700),
    double keyboard = 0,
  }) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(
            size: surface,
            viewInsets: EdgeInsets.only(bottom: keyboard),
            textScaler: const TextScaler.linear(1.3),
          ),
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            body: child,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('narrow 360px: dialog shell does not overflow', (tester) async {
    await pumpEditor(
      tester,
      child: BgSourceRuleEditorDialog(initial: _dirRule(), sortOrder: 0),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('保存'), findsOneWidget);
  });

  testWidgets('a rule pointing at a deleted tag does not crash the editor',
      (tester) async {
    // A live tag exists, but the rule references a DIFFERENT (deleted) id.
    // DropdownButtonFormField asserts when its value is not among the items;
    // the editor must fall back to a placeholder instead of red-screening.
    final alive = await DbModule.tagPlayRepo.createTag(name: 'alive');
    final missingId = alive.id + 9999;
    final rule = BgSourceRule(
      id: 'stale',
      kind: BgSourceRuleKind.tag,
      tagId: missingId,
    );

    await pumpEditor(
      tester,
      child: BgSourceRuleEditorDialog(initial: rule, sortOrder: 0),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('#$missingId'), findsOneWidget);
  });

  testWidgets('narrow 360px: sheet shell does not overflow', (tester) async {
    await pumpEditor(
      tester,
      child: BgSourceRuleEditorSheet(initial: _dirRule(), sortOrder: 0),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('保存'), findsOneWidget);
  });

  testWidgets('keyboard shown: sheet save stays above the keyboard',
      (tester) async {
    const surface = Size(360, 700);
    const keyboard = 300.0;
    await pumpEditor(
      tester,
      surface: surface,
      keyboard: keyboard,
      child: BgSourceRuleEditorSheet(initial: _dirRule(), sortOrder: 0),
    );
    expect(tester.takeException(), isNull);
    final saveRect = tester.getRect(find.text('保存'));
    expect(saveRect.bottom, lessThanOrEqualTo(surface.height - keyboard));
  });

  testWidgets('keyboard frames do not rebuild the form', (tester) async {
    const surface = Size(360, 700);
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    Future<void> pumpKeyboard(double keyboard) {
      return tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(
              size: surface,
              viewInsets: EdgeInsets.only(bottom: keyboard),
              textScaler: const TextScaler.linear(1.3),
            ),
            child: Scaffold(
              resizeToAvoidBottomInset: false,
              body:
                  BgSourceRuleEditorSheet(initial: _dirRule(), sortOrder: 0),
            ),
          ),
        ),
      );
    }

    var builds = 0;
    BgSourceRuleEditorForm.debugOnFormBuild = () => builds++;
    addTearDown(() => BgSourceRuleEditorForm.debugOnFormBuild = null);

    await pumpKeyboard(0);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Only keyboard height changes now — the cached form must not rebuild.
    builds = 0;
    await pumpKeyboard(300);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(builds, 0);
    expect(find.text('保存'), findsOneWidget);
  });
}
