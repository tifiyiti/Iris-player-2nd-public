import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/model/db/dao/bg_mapping_segments_dao.dart';
import 'package:iris/features/background_playback/model/db/dao/bg_mappings_dao.dart';
import 'package:iris/features/background_playback/model/db/repositories/background_mapping_repository.dart';
import 'package:iris/features/background_playback/model/domain/background_mapping.dart';
import 'package:iris/features/background_playback/model/enum/mapping_action.dart';
import 'package:iris/features/background_playback/services/mapping_staging_service.dart';
import 'package:iris/features/background_playback/store/use_background_mapping_staging_store.dart';
import 'package:iris/models/db/app_database.dart';

void main() {
  MappingSegment play(int start, int end) => MappingSegment(
        action: MappingAction.playMedia,
        fgStartMs: start,
        fgEndMs: end,
        bgStorageId: 'local',
        bgPath: 'Anime/B-side.mp4',
        bgStartMs: start,
        bgEndMs: end,
        bgStartN: start / 600000,
        bgEndN: end / 600000,
      );

  BackgroundMappingTimeline timeline(List<MappingSegment> segments) =>
      BackgroundMappingTimeline(
        storageId: 'local',
        path: 'Anime/Ep01.mp4',
        fgTotalMs: 600000,
        segments: segments,
      );

  group('BackgroundMappingStagingStore', () {
    test('stages, reports dirty and discards per fg', () {
      final store = BackgroundMappingStagingStore();
      const key = 'local:Anime/Ep01.mp4';
      expect(store.isDirty(key), isFalse);

      store.stage(timeline([play(0, 1000)]), baselineUpdatedAt: DateTime(2026));
      expect(store.isDirty(key), isTrue);
      expect(store.stagedFor(key)!.timeline.segments, hasLength(1));
      expect(store.dirtyKeys, {key});

      store.discard(key);
      expect(store.isDirty(key), isFalse);
      expect(store.hasStaged, isFalse);
    });

    test('discardAll clears every draft', () {
      final store = BackgroundMappingStagingStore();
      store.stage(timeline([play(0, 1000)]));
      store.stage(timeline([play(2000, 3000)]).copyWith(path: 'Anime/Ep02.mp4'));
      expect(store.hasStaged, isTrue);
      store.discardAll();
      expect(store.hasStaged, isFalse);
    });
  });

  group('BackgroundMappingStagingStore APB session overlay', () {
    const key = 'local:Anime/Ep01.mp4';

    test('stages and reads back an overlay without touching manager drafts', () {
      final store = BackgroundMappingStagingStore();
      expect(store.hasApbOverlay(key), isFalse);

      store.stageApbOverlay(timeline([play(0, 1000)]));

      expect(store.hasApbOverlay(key), isTrue);
      expect(store.apbOverlayFor(key)!.timeline.segments, hasLength(1));
      // The overlay must never masquerade as a dirty manager draft.
      expect(store.stagedFor(key), isNull);
      expect(store.isDirty(key), isFalse);
      expect(store.hasStaged, isFalse);
    });

    test('an overlay and a manager draft for the same fg coexist', () {
      final store = BackgroundMappingStagingStore();
      store.stage(timeline([play(0, 1000)]));
      store.stageApbOverlay(timeline([play(2000, 3000)]));

      expect(store.stagedFor(key)!.timeline.segments.single.fgStartMs, 0);
      expect(store.apbOverlayFor(key)!.timeline.segments.single.fgStartMs, 2000);
    });

    test('discardApbOverlay drops only the overlay', () {
      final store = BackgroundMappingStagingStore();
      store.stage(timeline([play(0, 1000)]));
      store.stageApbOverlay(timeline([play(2000, 3000)]));

      store.discardApbOverlay(key);
      expect(store.hasApbOverlay(key), isFalse);
      expect(store.isDirty(key), isTrue, reason: 'the manager draft survives');
    });

    test('discardAllApbOverlays clears every overlay, keeping drafts', () {
      final store = BackgroundMappingStagingStore();
      store.stage(timeline([play(0, 1000)]));
      store.stageApbOverlay(timeline([play(0, 1000)]));
      store.stageApbOverlay(
        timeline([play(2000, 3000)]).copyWith(path: 'Anime/Ep02.mp4'),
      );

      store.discardAllApbOverlays();

      expect(store.apbOverlayFor(key), isNull);
      expect(store.apbOverlayFor('local:Anime/Ep02.mp4'), isNull);
      expect(store.isDirty(key), isTrue, reason: 'manager drafts must survive');
    });
  });

  group('applyStagedMappingTimeline', () {
    late AppDatabase db;
    late BackgroundMappingRepository repo;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      repo = BackgroundMappingRepository(
        mappingsDao: BgMappingsDao(db),
        segmentsDao: BgMappingSegmentsDao(db),
        db: db,
      );
    });

    tearDown(() async => db.close());

    test('commits the draft when the baseline is unchanged', () async {
      await repo.saveTimeline(
        storageId: 'local',
        path: 'Anime/Ep01.mp4',
        fgTotalMs: 600000,
        segments: [play(0, 1000), play(2000, 3000)],
      );
      final committed = await repo.getTimelineForFg(
        storageId: 'local',
        path: 'Anime/Ep01.mp4',
      );

      final draft = committed!.copyWith(segments: [play(0, 1000)]);
      final outcome = await applyStagedMappingTimeline(
        staged: draft,
        baselineUpdatedAt: committed.updatedAt,
        repo: repo,
      );

      expect(outcome.status, MappingApplyStatus.ok);
      final reloaded = await repo.getTimelineForFg(
        storageId: 'local',
        path: 'Anime/Ep01.mp4',
      );
      expect(reloaded!.segments, hasLength(1));
    });

    test('refuses when the committed row changed since the baseline',
        () async {
      await repo.saveTimeline(
        storageId: 'local',
        path: 'Anime/Ep01.mp4',
        fgTotalMs: 600000,
        segments: [play(0, 1000)],
      );
      final committed = await repo.getTimelineForFg(
        storageId: 'local',
        path: 'Anime/Ep01.mp4',
      );

      // Simulate an external edit: apply with a stale baseline.
      final outcome = await applyStagedMappingTimeline(
        staged: committed!.copyWith(segments: [play(0, 500)]),
        baselineUpdatedAt: DateTime.fromMillisecondsSinceEpoch(0),
        repo: repo,
      );
      expect(outcome.status, MappingApplyStatus.conflict);
    });

    test('treats a deleted committed row as a conflict', () async {
      await repo.saveTimeline(
        storageId: 'local',
        path: 'Anime/Ep01.mp4',
        fgTotalMs: 600000,
        segments: [play(0, 1000)],
      );
      final committed = await repo.getTimelineForFg(
        storageId: 'local',
        path: 'Anime/Ep01.mp4',
      );
      await repo.deleteForFg(storageId: 'local', path: 'Anime/Ep01.mp4');

      final outcome = await applyStagedMappingTimeline(
        staged: committed!,
        baselineUpdatedAt: committed.updatedAt,
        repo: repo,
      );
      expect(outcome.status, MappingApplyStatus.conflict);
    });

    test('reports invalid drafts through the repository validator', () async {
      await repo.saveTimeline(
        storageId: 'local',
        path: 'Anime/Ep01.mp4',
        fgTotalMs: 600000,
        segments: [play(0, 1000)],
      );
      final committed = await repo.getTimelineForFg(
        storageId: 'local',
        path: 'Anime/Ep01.mp4',
      );

      final outcome = await applyStagedMappingTimeline(
        // A degenerate fg range fails MappingValidationError. (Overlaps are
        // legal since v34 — they resolve by activation order.)
        staged: committed!.copyWith(segments: [play(1000, 1000)]),
        baselineUpdatedAt: committed.updatedAt,
        repo: repo,
      );
      expect(outcome.status, MappingApplyStatus.invalid);
    });
  });

  group('replaceSegmentBg', () {
    test('swaps the bg of the targeted segment only, keeping its span', () {
      final t = BackgroundMappingTimeline(
        storageId: 'local',
        path: 'Anime/Ep01.mp4',
        fgTotalMs: 600000,
        segments: [
          play(0, 1000).copyWith(id: 1),
          play(2000, 3000).copyWith(id: 2),
        ],
      );

      final next = replaceSegmentBg(
        t,
        t.segments[1],
        bgStorageId: 'local',
        bgPath: 'Anime/New-side.mp4',
        bgTotalMs: 120000,
      );

      expect(next.segments[0].bgPath, 'Anime/B-side.mp4');
      expect(next.segments[1].bgPath, 'Anime/New-side.mp4');
      // Span untouched (id 2 target had fg 2000..3000, offset 0).
      expect(next.segments[1].fgStartMs, 2000);
      expect(next.segments[1].fgEndMs, 3000);
      expect(next.segments[1].bgStartMs, 2000);
      expect(next.segments[1].bgEndMs, 3000);
      expect(next.segments[1].bgEndN, closeTo(3000 / 120000, 1e-9));
    });
  });
}
