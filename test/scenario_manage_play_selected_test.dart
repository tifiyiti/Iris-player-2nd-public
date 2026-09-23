import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/scenario_playback/model/enum/scenario_source_kind.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';
import 'package:iris/features/scenario_playback/view/sources/paged_scenario_sources_data_source.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/store/warning_dialogs.dart';

/// F-007: the scenario manage sources multi-select gains `Play selected items`
/// — an Override that asks for confirmation (D24), keeps saved `recursive`
/// flags for dir sources (v2-D1) and maps includes/files to explicit items
/// (v6-D40).
void main() {
  setUpAll(() async {
    final db = AppDatabase(NativeDatabase.memory());
    DbModule.init(db);
    usePlaybackScenarioStore();
    await usePlaybackScenarioStore().initialized;
    await runZonedGuarded(() async {
      usePlayQueueStore();
      await usePlayQueueStore().initialized;
      useAppStore();
      await useAppStore().initialized;
      // Play actions route through runPlayAction(WithNoMediaConfirm), which
      // shows the first-use workspace notice (kWarningScenarioWorkspace). These
      // tests cover the override/selected-items install, not the notice, so
      // pre-suppress it as the real second-use onward state does.
      await useAppStore().suppressWarning(kWarningScenarioWorkspace);
    }, (Object e, StackTrace st) {});
  });

  setUp(() async {
    final store = usePlaybackScenarioStore();
    final sys = await store.ensureSystemPlayingScenario();
    await store.setActiveScenario(sys.id);
    await store.clearSources(sys.id);
    await store.clearExplicitItems(sys.id);
    await store.clearTemporaryExcludes(sys.id);
  });

  Future<void> seedFile(String storageId, String p) async {
    await DbModule.mediaNodesDao.deleteNode(storageId, p);
    final segments = p.split('/');
    await DbModule.mediaNodesDao.insertNode(MediaNode.file(
      id: 'f:$storageId:$p',
      storageId: storageId,
      path: segments,
      name: segments.last,
      mediaType: MediaType.video,
    ));
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets(
      'F-007 play selected items overrides with saved recursive flags and '
      'includes', (tester) async {
    // Elapse fake time first so drift's executor deliveries (microtasks that
    // need a real frame) complete for the awaits below.
    await tester.pump(const Duration(milliseconds: 100));
    final store = usePlaybackScenarioStore();
    final sys = await store.ensureSystemPlayingScenario();
    await store.setActiveScenario(sys.id);
    await seedFile('s', 'dir/a.mp4');
    await seedFile('s', 'inc.mp4');
    await store.addSource(storageId: 's', path: 'dir', recursive: false);
    await store.addSource(
      storageId: 's',
      path: 'single.mp4',
      recursive: false,
      kind: ScenarioSourceKind.file,
    );
    await store.addExplicitItemFor(
      scenarioId: sys.id,
      storageId: 's',
      path: 'inc.mp4',
    );
    final userSources = await store.getSources(sys.id);
    final dirSource = userSources.firstWhere((s) => s.path == 'dir');
    final fileSource = userSources.firstWhere((s) => s.path == 'single.mp4');

    final ds = PagedScenarioSourcesDataSource(
      scenarioId: sys.id,
      embeddedInStoragesDb: true,
    );
    addTearDown(ds.dispose);

    ScenarioManageItem item({
      required ScenarioManageItemKind kind,
      int? sourceId,
      required String path,
      bool isFile = false,
    }) =>
        ScenarioManageItem(
          kind: kind,
          group: isFile
              ? ScenarioManageGroup.itemSources
              : ScenarioManageGroup.dirSources,
          sourceId: sourceId,
          title: path,
          subtitle: '',
          sortName: path,
          containerKey: 's:/$path',
          storageName: 'S',
          storageId: 's',
          path: path,
          isFile: isFile,
        );

    final dirItem = item(
      kind: ScenarioManageItemKind.source,
      sourceId: dirSource.id,
      path: 'dir',
    );
    final includeItem = item(
      kind: ScenarioManageItemKind.include,
      path: 'inc.mp4',
      isFile: true,
    );
    final fileItem = item(
      kind: ScenarioManageItemKind.source,
      sourceId: fileSource.id,
      path: 'single.mp4',
      isFile: true,
    );

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          final actions = ds.buildCustomSelectionActions(context);
          final play = actions.firstWhere(
              (a) => a.label == 'Play selected items');
          return Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => play.onPressed(
                    context, {dirItem, includeItem, fileItem}),
                child: const Text('go'),
              ),
            ),
          );
        },
      ),
    ));
    // Deferred l10n delegates load async — settle before tapping.
    await tester.pumpAndSettle();
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 100));

    // v3-D3/D24: confirmation dialog appears first.
    expect(find.text('Override current playing?'), findsOneWidget);
    await tester.tap(find.text('Override and play'));
    await settle(tester);

    // Workspace override: dir source keeps its non-recursive flag (v2-D1);
    // includes + file-kind sources map to explicit items (v6-D40).
    final wsSys = await store.ensureSystemPlayingScenario();
    final wsSources = await store.getSources(wsSys.id);
    expect(wsSources.map((s) => s.path), contains('dir'));
    expect(wsSources.where((s) => s.path == 'dir').first.recursive, isFalse);
    final wsItems = await DbModule.scenarioRepo.getExplicitItems(wsSys.id);
    expect(wsItems.map((e) => e.path), containsAll(['inc.mp4', 'single.mp4']));
  });

  testWidgets('F-007 cancel keeps the selection and does not override',
      (tester) async {
    await tester.pump(const Duration(milliseconds: 100));
    final store = usePlaybackScenarioStore();
    final sys = await store.ensureSystemPlayingScenario();
    await store.setActiveScenario(sys.id);
    await seedFile('s', 'dir/a.mp4');
    await store.addSource(storageId: 's', path: 'dir', recursive: false);
    final userSources = await store.getSources(sys.id);
    final dirSource = userSources.first;

    final ds = PagedScenarioSourcesDataSource(
      scenarioId: sys.id,
      embeddedInStoragesDb: true,
    );
    addTearDown(ds.dispose);

    final dirItem = ScenarioManageItem(
      kind: ScenarioManageItemKind.source,
      group: ScenarioManageGroup.dirSources,
      sourceId: dirSource.id,
      title: 'dir',
      subtitle: '',
      sortName: 'dir',
      containerKey: 's:/dir',
      storageName: 'S',
      storageId: 's',
      path: 'dir',
    );

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          final actions = ds.buildCustomSelectionActions(context);
          final play =
              actions.firstWhere((a) => a.label == 'Play selected items');
          return Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => play.onPressed(context, {dirItem}),
                child: const Text('go'),
              ),
            ),
          );
        },
      ),
    ));
    // Deferred l10n delegates load async — settle before tapping.
    await tester.pumpAndSettle();
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Override current playing?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);

    // D24: cancel keeps the workspace unchanged — the pre-existing source
    // survives (the override never ran).
    final wsSys2 = await store.ensureSystemPlayingScenario();
    final wsSources = await store.getSources(wsSys2.id);
    expect(wsSources.map((s) => s.path), contains('dir'));
    expect(wsSources.where((s) => s.path == 'dir').first.recursive, isFalse);
    expect(await DbModule.scenarioRepo.getExplicitItems(wsSys2.id), isEmpty);
  });
}
