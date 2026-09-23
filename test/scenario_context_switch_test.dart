import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/scenario_playback/actions/scenario_resolved_actions.dart';
import 'package:iris/features/scenario_playback/playback/scenario_playback_provider.dart';
import 'package:iris/features/scenario_playback/resolver/scenario_resolver.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';

/// Scenario context-switch contract (per-entry independent playback):
/// - switching to a scenario feeds that scenario's OWN current video;
/// - switching to an EMPTY scenario unloads the player (blank) instead of
///   continuing the previous scenario's media;
/// - autoplay is honored (warm-start pause stays paused);
/// - the per-scenario locate cache is FIFO-bounded (max 8), lossless.
void main() {
  late AppDatabase db;
  late ScenarioResolver resolver;

  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory());
    DbModule.init(db);
    await runZonedGuarded(() async {
      usePlaybackScenarioStore();
      await usePlaybackScenarioStore().initialized;
      usePlayQueueStore();
      await usePlayQueueStore().initialized;
      useAppStore();
      await useAppStore().initialized;
    }, (Object e, StackTrace st) {});
  });

  tearDownAll(() => db.close());

  setUp(() async {
    resolver = ScenarioResolver(
      repo: DbModule.scenarioRepo,
      nodeRepo: DbModule.mediaNodeRepo,
      scopedMediaTypes: () => null,
    );
    // A SystemPlaying row must exist before any workspace refresh (cold-start
    // parity); keep it active as the baseline context.
    final store = usePlaybackScenarioStore();
    final sys = await store.ensureSystemPlayingScenario();
    await store.setActiveScenario(sys.id);
  });

  Future<void> seedFile(String folder, String name) async {
    try {
      await DbModule.mediaNodesDao.insertNode(MediaNode.file(
        id: 'f:st1:$folder/$name',
        storageId: 'st1',
        path: [folder, name],
        name: name,
        mediaType: MediaType.video,
      ));
    } catch (_) {
      // The in-memory DB persists across tests in this file; a duplicate seed
      // is harmless.
    }
  }

  /// Creates an independent entry workspace whose queue is [folder] and whose
  /// current item is its first file.
  Future<String> workspaceWith(String folder, String name) async {
    await seedFile(folder, name);
    final store = usePlaybackScenarioStore();
    final ws = await store.ensureEntryWorkspace(null);
    await DbModule.scenarioRepo.addSource(
      scenarioId: ws.id,
      storageId: 'st1',
      path: folder,
      recursive: true,
    );
    await store.setActiveScenario(ws.id);
    final page = await resolver.resolvePage(
      scenarioId: ws.id,
      page: 0,
      pageSize: 10,
    );
    await store.setCurrentItem(occurrence: page.items.first.occurrenceId);
    return ws.id;
  }

  ScenarioPlaybackProvider provider() =>
      ScenarioPlaybackProvider(store: usePlaybackScenarioStore());

  test('switching scenarios feeds each one\'s own current video', () async {
    final a = await workspaceWith('A', 'a.mp4');
    final b = await workspaceWith('B', 'b.mp4');

    await ScenarioResolvedActions.switchPlaybackContext(a,
        autoplay: true, provider: provider());
    expect(usePlayQueueStore().state.playQueue.single.file.name, 'a.mp4');

    await ScenarioResolvedActions.switchPlaybackContext(b,
        autoplay: true, provider: provider());
    expect(usePlayQueueStore().state.playQueue.single.file.name, 'b.mp4');

    // Switching back restores A's own current video (progress is global).
    await ScenarioResolvedActions.switchPlaybackContext(a,
        autoplay: true, provider: provider());
    expect(usePlayQueueStore().state.playQueue.single.file.name, 'a.mp4');
  });

  test('currentItemFor resolves the scenario\'s OWN item, not the active one',
      () async {
    final a = await workspaceWith('A', 'a.mp4');
    final b = await workspaceWith('B', 'b.mp4');
    final store = usePlaybackScenarioStore();

    // Viewing another scenario's queue must NEVER report the active
    // workspace's item (the reported "open another queue, scrolls to an
    // unrelated row" bug).
    await store.setActiveScenario(a);
    final active = await store.getCurrentItem();
    final other = await store.currentItemFor(b);
    expect(active?.media.name, 'a.mp4');
    expect(other?.media.name, 'b.mp4');
    expect(other?.mediaKey, isNot(active?.mediaKey));
  });

  test('switching to an empty scenario clears the player feed', () async {
    final a = await workspaceWith('A', 'a.mp4');
    await ScenarioResolvedActions.switchPlaybackContext(a,
        autoplay: true, provider: provider());
    expect(usePlayQueueStore().state.playQueue, isNotEmpty);
    useAppStore().set(useAppStore().state.copyWith(autoPlay: true));

    final store = usePlaybackScenarioStore();
    final empty = await store.ensureEntryWorkspace(null);

    await ScenarioResolvedActions.switchPlaybackContext(empty.id,
        autoplay: true, provider: provider());

    expect(usePlayQueueStore().state.playQueue, isEmpty,
        reason: 'empty context must not keep the previous video');
    expect(useAppStore().state.autoPlay, isFalse);
  });

  test('play(autoplay: false) loads the media without play intent', () async {
    final a = await workspaceWith('A', 'a.mp4');
    final store = usePlaybackScenarioStore();
    await store.setActiveScenario(a);

    final provider = ScenarioPlaybackProvider(store: store);
    useAppStore().set(useAppStore().state.copyWith(autoPlay: false));

    final entry = await provider.itemAt(0);
    await provider.play(entry!, autoplay: false);

    expect(useAppStore().state.autoPlay, isFalse);
    expect(usePlayQueueStore().state.playQueue.single.file.name, 'a.mp4');
  });

  test('session cache is FIFO-bounded at 8', () {
    expect(ScenarioPlaybackProvider.maxCachedSessions, 8);
  });
}
