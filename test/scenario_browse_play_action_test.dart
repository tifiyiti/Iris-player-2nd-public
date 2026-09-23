import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/app_identity/model/domain/app_identity_entry.dart';
import 'package:iris/features/app_identity/store/use_app_identity_store.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/paginated_browser/models/generic_browser_models.dart';
import 'package:iris/features/scenario_playback/actions/scenario_playback_actions.dart';
import 'package:iris/features/scenario_playback/playback/playback_provider_registry.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';
import 'package:iris/features/scenario_playback/view/browse/paged_scenario_browse_data_source.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/store/warning_dialogs.dart';

/// Browse-page Play action (`ScenarioManagedPlayActions.playManagedScenario`):
/// SystemPlaying (or the active entry's own workspace) plays directly, while a
/// saved scenario overrides the CURRENT playback workspace behind a suppressible
/// confirmation (box ticked by default).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final db = AppDatabase(NativeDatabase.memory());
    DbModule.init(db);
    PlaybackProviderRegistry.init();
    usePlaybackScenarioStore();
    await usePlaybackScenarioStore().initialized;
    await runZonedGuarded(() async {
      usePlayQueueStore();
      await usePlayQueueStore().initialized;
      useAppStore();
      await useAppStore().initialized;
    }, (Object e, StackTrace st) {});
  });

  setUp(() async {
    final store = usePlaybackScenarioStore();
    final sys = await store.ensureSystemPlayingScenario();
    await store.refreshScenarios();
    await store.setActiveScenario(sys.id);
    await store.clearSources(sys.id);
    await store.clearExplicitItems(sys.id);
    await store.clearTemporaryExcludes(sys.id);
    await useAppIdentityStore().setActiveEntry(null);
    await useAppStore().resetSuppressedWarnings();
    await useAppStore().updateAutoPlay(false);
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

  Future<void> pumpPlay(
    WidgetTester tester,
    String scenarioId,
    void Function() onExit,
  ) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => ScenarioPlaybackActions.playManagedScenario(
                context,
                scenarioId: scenarioId,
                onExitAfterPlay: onExit,
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ));
    // Deferred l10n delegates load async — settle before tapping.
    await tester.pumpAndSettle();
    await tester.tap(find.text('go'));
    await settle(tester);
  }

  testWidgets('SystemPlaying plays directly: no override prompt, manager exits',
      (tester) async {
    final store = usePlaybackScenarioStore();
    final sys = await store.ensureSystemPlayingScenario();
    await seedFile('s', 'one.mp4');
    await store.addExplicitItemFor(
      scenarioId: sys.id,
      storageId: 's',
      path: 'one.mp4',
    );

    var exited = false;
    await pumpPlay(tester, sys.id, () => exited = true);

    expect(find.text('Override current playing?'), findsNothing);
    expect(exited, isTrue);
    // Paused before the action: playback started on the workspace item.
    expect(await store.getCurrentItem(), isNotNull);
  });

  testWidgets(
      'saved scenario prompts first, box defaults ticked, Cancel keeps the '
      'workspace', (tester) async {
    final store = usePlaybackScenarioStore();
    final sys = await store.ensureSystemPlayingScenario();
    final saved = await store.createScenario('Saved');
    await seedFile('s', 'other.mp4');
    await DbModule.scenarioRepo.addSource(
      scenarioId: saved.id,
      storageId: 's',
      path: 'other',
      recursive: false,
    );

    var exited = false;
    await pumpPlay(tester, saved.id, () => exited = true);

    expect(find.text('Override current playing?'), findsOneWidget);
    final checkbox =
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile));
    expect(checkbox.value, isTrue, reason: 'suppress box defaults ticked');

    await tester.tap(find.text('Cancel'));
    await settle(tester);

    expect(exited, isFalse);
    expect(await store.getSources(sys.id), isEmpty);
    expect(useAppStore().state.suppressedWarnings,
        isNot(contains(kWarningScenarioBrowsePlayOverride)));
  });

  testWidgets(
      'saved scenario Override and play replaces the workspace and suppresses '
      'future prompts', (tester) async {
    final store = usePlaybackScenarioStore();
    final sys = await store.ensureSystemPlayingScenario();
    final saved = await store.createScenario('Saved');
    await seedFile('s', 'other.mp4');
    await DbModule.scenarioRepo.addSource(
      scenarioId: saved.id,
      storageId: 's',
      path: 'other',
      recursive: false,
    );

    var exited = false;
    await pumpPlay(tester, saved.id, () => exited = true);

    expect(find.text('Override current playing?'), findsOneWidget);
    await tester.tap(find.text('Override and play'));
    await settle(tester);

    expect(exited, isTrue);
    expect((await store.getSources(sys.id)).map((s) => s.path),
        contains('other'));
    expect(useAppStore().state.suppressedWarnings,
        contains(kWarningScenarioBrowsePlayOverride));

    // Second run: already suppressed -> no prompt, override still applies.
    exited = false;
    await pumpPlay(tester, saved.id, () => exited = true);
    expect(find.text('Override current playing?'), findsNothing);
    expect(exited, isTrue);
  });

  testWidgets('browse bottom bar exposes the Play action', (tester) async {
    final store = usePlaybackScenarioStore();
    final sys = await store.ensureSystemPlayingScenario();
    final ds = PagedScenarioBrowseDataSource(scenarioId: sys.id);
    addTearDown(ds.dispose);

    List<PageAction> actions = const [];
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (context) {
        actions = ds.buildCustomPageActions(context);
        return const SizedBox.shrink();
      }),
    ));
    await tester.pumpAndSettle();

    expect(actions.map((a) => a.label), contains('Play'));
  });

  testWidgets('override targets the active entry workspace, not SystemPlaying',
      (tester) async {
    final store = usePlaybackScenarioStore();
    final sys = await store.ensureSystemPlayingScenario();
    final entryWs = await store.ensureEntryWorkspace(null);
    final identity = useAppIdentityStore();
    await identity.upsertEntry(AppIdentityEntry(
      id: 'e1',
      name: 'Entry',
      workspaceScenarioId: entryWs.id,
    ));
    await identity.setActiveEntry('e1');

    final saved = await store.createScenario('Saved');
    await seedFile('s', 'other.mp4');
    await DbModule.scenarioRepo.addSource(
      scenarioId: saved.id,
      storageId: 's',
      path: 'other',
      recursive: false,
    );

    var exited = false;
    await pumpPlay(tester, saved.id, () => exited = true);

    expect(find.text('Override current playing?'), findsOneWidget);
    await tester.tap(find.text('Override and play'));
    await settle(tester);

    expect(exited, isTrue);
    expect((await store.getSources(entryWs.id)).map((s) => s.path),
        contains('other'));
    // SystemPlaying must stay untouched.
    expect(await store.getSources(sys.id), isEmpty);
  });
}
