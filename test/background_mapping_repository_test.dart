import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/model/db/dao/bg_mapping_segments_dao.dart';
import 'package:iris/features/background_playback/model/db/dao/bg_mappings_dao.dart';
import 'package:iris/features/background_playback/model/db/repositories/background_mapping_repository.dart';
import 'package:iris/features/background_playback/model/domain/background_mapping.dart';
import 'package:iris/features/background_playback/model/enum/mapping_action.dart';
import 'package:iris/models/db/app_database.dart';

void main() {
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

  const fgStorage = 'local';
  const fgPath = 'Anime/Ep01.mp4';

  MappingSegment play(int start, int end, {int id = 0}) => MappingSegment(
        id: id,
        action: MappingAction.playMedia,
        fgStartMs: start,
        fgEndMs: end,
        fgStartN: start / 600000,
        fgEndN: end / 600000,
        bgStorageId: 'local',
        bgPath: 'Anime/B-side.mp4',
        bgStartMs: 1000,
        bgEndMs: 5000,
        bgStartN: 1 / 60,
        bgEndN: 5 / 60,
        adjustedRate: 1.0,
      );

  test('save + roundtrip a timeline (playMedia + silence), sorted', () async {
    final segments = [
      play(120000, 240000),
      const MappingSegment(
        action: MappingAction.silence,
        fgStartMs: 300000,
        fgEndMs: 360000,
        fgStartN: 0.5,
        fgEndN: 0.6,
      ),
    ];
    await repo.saveTimeline(
      storageId: fgStorage,
      path: fgPath,
      fgTotalMs: 600000,
      segments: segments,
    );

    final loaded = await repo.getTimelineForFg(storageId: fgStorage, path: fgPath);
    expect(loaded, isNotNull);
    expect(loaded!.storageId, fgStorage);
    expect(loaded.path, fgPath);
    expect(loaded.fgTotalMs, 600000);
    expect(loaded.segments, hasLength(2));
    expect(loaded.segments.first.action, MappingAction.playMedia);
    expect(loaded.segments.first.fgStartMs, 120000);
    expect(loaded.segments.first.bgPath, 'Anime/B-side.mp4');
    expect(loaded.segments.last.action, MappingAction.silence);
    expect(loaded.sortedSegments.map((s) => s.fgStartMs), [120000, 300000]);
  });

  test('paths are canonicalized (leading slash tolerated)', () async {
    await repo.saveTimeline(
      storageId: fgStorage,
      path: '/Anime/Ep01.mp4',
      segments: [play(0, 1000)],
    );
    final loaded =
        await repo.getTimelineForFg(storageId: fgStorage, path: 'Anime/Ep01.mp4');
    expect(loaded, isNotNull);
    expect(loaded!.path, 'Anime/Ep01.mp4');
  });

  test('resave replaces the previous segment set atomically', () async {
    await repo.saveTimeline(
      storageId: fgStorage,
      path: fgPath,
      fgTotalMs: 600000,
      segments: [play(0, 1000)],
    );
    await repo.saveTimeline(
      storageId: fgStorage,
      path: fgPath,
      fgTotalMs: 700000,
      segments: [
        play(500, 900),
        const MappingSegment(
            action: MappingAction.silence, fgStartMs: 1000, fgEndMs: 1200),
      ],
    );
    final loaded = await repo.getTimelineForFg(storageId: fgStorage, path: fgPath);
    expect(loaded!.fgTotalMs, 700000);
    expect(loaded.segments, hasLength(2));
  });

  test('deleteForFg clears the timeline', () async {
    await repo.saveTimeline(
      storageId: fgStorage,
      path: fgPath,
      segments: [play(0, 1000)],
    );
    await repo.deleteForFg(storageId: fgStorage, path: fgPath);
    final loaded = await repo.getTimelineForFg(storageId: fgStorage, path: fgPath);
    expect(loaded, isNull);
  });

  group('validation', () {
    test('overlapping fg ranges are allowed and persist activation fields',
        () async {
      await repo.saveTimeline(
        storageId: fgStorage,
        path: fgPath,
        fgTotalMs: 600000,
        segments: [
          play(0, 1000),
          play(900, 2000).copyWith(activeSeq: 5, isActive: false),
        ],
      );

      final loaded =
          await repo.getTimelineForFg(storageId: fgStorage, path: fgPath);
      expect(loaded!.segments, hasLength(2));
      final disabled = loaded.segments.firstWhere((s) => s.fgStartMs == 900);
      expect(disabled.isActive, isFalse);
      expect(disabled.activeSeq, 5);
    });

    test('negative activeSeq is rejected', () async {
      await expectLater(
        repo.saveTimeline(
          storageId: fgStorage,
          path: fgPath,
          segments: [play(0, 1000).copyWith(activeSeq: -1)],
        ),
        throwsA(isA<MappingValidationError>()),
      );
    });

    test('playMedia without a bg file is rejected', () async {
      await expectLater(
        repo.saveTimeline(
          storageId: fgStorage,
          path: fgPath,
          segments: const [
            MappingSegment(
              action: MappingAction.playMedia,
              fgStartMs: 0,
              fgEndMs: 1000,
            ),
          ],
        ),
        throwsA(isA<MappingValidationError>()),
      );
    });

    test('silence carrying a bg file is rejected', () async {
      await expectLater(
        repo.saveTimeline(
          storageId: fgStorage,
          path: fgPath,
          segments: [
            play(0, 1000).copyWith(action: MappingAction.silence),
          ],
        ),
        throwsA(isA<MappingValidationError>()),
      );
    });

    test('degenerate fg range is rejected', () async {
      await expectLater(
        repo.saveTimeline(
          storageId: fgStorage,
          path: fgPath,
          segments: [play(500, 500)],
        ),
        throwsA(isA<MappingValidationError>()),
      );
    });
  });
}
