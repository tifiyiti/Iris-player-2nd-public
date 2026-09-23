import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/scenario_playback/commands/scenario_commands.dart';
import 'package:iris/features/scenario_playback/model/db/dao/scenario_excludes_dao.dart';
import 'package:iris/features/scenario_playback/model/db/dao/scenario_explicit_items_dao.dart';
import 'package:iris/features/scenario_playback/model/db/dao/scenario_sources_dao.dart';
import 'package:iris/features/scenario_playback/model/db/dao/scenario_states_dao.dart';
import 'package:iris/features/scenario_playback/model/db/dao/scenarios_dao.dart';
import 'package:iris/features/scenario_playback/model/db/repositories/scenario_repository.dart';
import 'package:iris/features/scenario_playback/model/enum/scenario_kind.dart';
import 'package:iris/models/db/app_database.dart';

/// Independent desktop entries own their OWN workspace row
/// (`ScenarioKind.entryWorkspace`) in the shared database, so switching
/// entries never disturbs each other or the default SystemPlaying context.
void main() {
  group('entry workspace isolation', () {
    late AppDatabase db;
    late ScenarioRepository repo;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      repo = ScenarioRepository(
        scenariosDao: ScenariosDao(db),
        sourcesDao: ScenarioSourcesDao(db),
        itemsDao: ScenarioExplicitItemsDao(db),
        excludesDao: ScenarioExcludesDao(db),
        statesDao: ScenarioStatesDao(db),
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('each independent entry gets a distinct workspace row', () async {
      final sys = await repo.ensureSystemPlayingScenario();
      final a = await repo.createEntryWorkspace();
      final b = await repo.createEntryWorkspace();

      expect(a.type, ScenarioKind.entryWorkspace);
      expect(b.type, ScenarioKind.entryWorkspace);
      expect(a.version, isNull);
      expect({sys.id, a.id, b.id}.length, 3);
    });

    test('workspaces are not deletable through the scenario UI', () async {
      final sys = await repo.ensureSystemPlayingScenario();
      final ws = await repo.createEntryWorkspace();
      expect(await repo.deleteScenario(sys.id), isFalse);
      expect(await repo.deleteScenario(ws.id), isFalse);

      final saved = await repo.createScenario(name: 'Saved');
      expect(await repo.deleteScenario(saved.id), isTrue);
    });

    test('deleteEntryWorkspace removes the row and its records', () async {
      final ws = await repo.createEntryWorkspace();
      await repo.addSource(
        scenarioId: ws.id,
        storageId: 'st1',
        path: 'Anime',
        recursive: true,
      );

      await repo.deleteEntryWorkspace(ws.id);

      expect(await repo.getScenario(ws.id), isNull);
      expect(await repo.getSources(ws.id), isEmpty);
    });

    test('userSaved filter (the scenario list) excludes workspaces', () async {
      final sys = await repo.ensureSystemPlayingScenario();
      final ws = await repo.createEntryWorkspace();
      final saved = await repo.createScenario(name: 'Saved');

      final all = await repo.getAllScenarios();
      final listed = all
          .where((s) => s.type == ScenarioKind.userSaved)
          .map((s) => s.id)
          .toList();

      expect(all.map((s) => s.id), containsAll([sys.id, ws.id, saved.id]));
      expect(listed, [saved.id]);
    });

    test('overriding an entry workspace never touches SystemPlaying', () async {
      final sys = await repo.ensureSystemPlayingScenario();
      final ws = await repo.createEntryWorkspace();
      final saved = await repo.createScenario(name: 'Anime');

      await repo.addSource(
        scenarioId: sys.id,
        storageId: 'st1',
        path: 'Default',
      );
      await repo.addSource(
        scenarioId: saved.id,
        storageId: 'st1',
        path: 'Anime',
        recursive: true,
      );

      await ScenarioCommands.override(
        workspace: ws,
        source: saved,
        repo: repo,
      );

      final sysPaths = (await repo.getSources(sys.id)).map((s) => s.path);
      final wsPaths = (await repo.getSources(ws.id)).map((s) => s.path);

      expect(sysPaths, contains('Default'));
      expect(sysPaths, isNot(contains('Anime')));
      expect(wsPaths, contains('Anime'));
      expect(wsPaths, isNot(contains('Default')));
    });
  });
}
