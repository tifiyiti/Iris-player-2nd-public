import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/scenario_playback/actions/media_revision_actions.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';
import 'package:iris/features/scenario_playback/view/queue/paged_scenario_media_data_source.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';

/// The shared media-revision funnel: a storagedb scan / directory sync routes
/// through [MediaRevisionActions.mediaNodesChanged], which must (a) change the
/// derived-index signature so newly scanned nodes resolve, and (b) re-fetch an
/// already-open queue view in place.
void main() {
  late AppDatabase db;

  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory());
    DbModule.init(db);
    usePlaybackScenarioStore();
    await usePlaybackScenarioStore().initialized;
    usePlayQueueStore();
    await usePlayQueueStore().initialized;
    useAppStore();
    await useAppStore().initialized;
  });

  tearDownAll(() => db.close());

  test('mediaNodesChanged invalidates the index and refetches an open queue',
      () async {
    final store = usePlaybackScenarioStore();
    final sys = await store.ensureSystemPlayingScenario();
    await store.clearSources(sys.id);
    await DbModule.scenarioRepo.addSource(
      scenarioId: sys.id,
      storageId: 'st1',
      path: 'q1',
      recursive: true,
    );
    await DbModule.mediaNodesDao.insertNode(MediaNode.file(
      id: 'f:st1:q1/a.mp4',
      storageId: 'st1',
      path: ['q1', 'a.mp4'],
      name: 'a.mp4',
      mediaType: MediaType.video,
    ));

    final ds = PagedScenarioMediaDataSource(scenarioId: sys.id);
    // Let the constructor's initial fetch settle.
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(ds.totalItems, 1);

    // A scan writes a new node WITHOUT touching the scenario definition.
    await DbModule.mediaNodesDao.insertNode(MediaNode.file(
      id: 'f:st1:q1/b.mp4',
      storageId: 'st1',
      path: ['q1', 'b.mp4'],
      name: 'b.mp4',
      mediaType: MediaType.video,
    ));

    await MediaRevisionActions.mediaNodesChanged(const ['st1']);
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(ds.totalItems, 2,
        reason: 'a scan-only media change must become visible to playback');
    ds.dispose();
  });
}
