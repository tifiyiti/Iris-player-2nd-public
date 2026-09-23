import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/model/db/dao/bg_mapping_segments_dao.dart';
import 'package:iris/features/background_playback/model/db/dao/bg_mappings_dao.dart';
import 'package:iris/features/background_playback/model/db/repositories/background_mapping_repository.dart';
import 'package:iris/features/background_playback/model/domain/background_mapping.dart';
import 'package:iris/features/background_playback/model/domain/background_mapping_summary.dart';
import 'package:iris/features/background_playback/model/enum/mapping_action.dart';
import 'package:iris/features/background_playback/resolver/mapping_binding.dart';
import 'package:iris/features/background_playback/resolver/mapping_timeline_math.dart';
import 'package:iris/features/media_library/model/enum/media_node.dart';
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

  MappingSegment play(int start, int end, {String bg = 'Anime/B-side.mp4'}) =>
      MappingSegment(
        action: MappingAction.playMedia,
        fgStartMs: start,
        fgEndMs: end,
        fgStartN: start / 600000,
        fgEndN: end / 600000,
        bgStorageId: 'local',
        bgPath: bg,
        bgStartMs: 1000,
        bgEndMs: 5000,
        bgStartN: 1 / 60,
        bgEndN: 5 / 60,
        adjustedRate: 1.0,
      );

  Future<void> seedNode(
    String path, {
    String? name,
    int? durationMs,
  }) {
    return db.into(db.mediaNodesTable).insert(
          MediaNodesTableCompanion.insert(
            storageId: 'local',
            path: path,
            name: name ?? path.split('/').last,
            nodeKind: MediaNodeKind.file,
            durationMs: Value(durationMs),
          ),
        );
  }

  group('repository listing', () {
    test('listSummaries returns one row per fg with counts and bg names',
        () async {
      await repo.saveTimeline(
        storageId: 'local',
        path: 'Anime/Ep01.mp4',
        fgTotalMs: 600000,
        segments: [play(0, 1000), play(2000, 3000, bg: 'Anime/C-side.mp4')],
      );
      await repo.saveTimeline(
        storageId: 'local',
        path: 'Anime/Ep02.mp4',
        fgTotalMs: 500000,
        segments: [play(0, 1000)],
      );
      await seedNode('Anime/Ep01.mp4', name: 'Episode 01');

      final summaries = await repo.listSummaries();
      expect(summaries, hasLength(2));
      final ep1 = summaries.firstWhere((s) => s.path == 'Anime/Ep01.mp4');
      expect(ep1.segmentCount, 2);
      expect(ep1.fgTotalMs, 600000);
      expect(ep1.fgName, 'Episode 01');
      expect(ep1.displayName, 'Episode 01');
      expect(ep1.hasFgDuration, isTrue);
      expect(ep1.bgNames, containsAll(['B-side.mp4', 'C-side.mp4']));
    });

    test('fg duration falls back to media_nodes.durationMs; null disables',
        () async {
      await repo.saveTimeline(
        storageId: 'local',
        path: 'Anime/Ep03.mp4',
        segments: [play(0, 1000)],
      );
      await seedNode('Anime/Ep03.mp4', durationMs: 123456);
      await repo.saveTimeline(
        storageId: 'local',
        path: 'Anime/Ep04.mp4',
        segments: [play(0, 1000)],
      );

      final summaries = await repo.listSummaries();
      final ep3 = summaries.firstWhere((s) => s.path == 'Anime/Ep03.mp4');
      final ep4 = summaries.firstWhere((s) => s.path == 'Anime/Ep04.mp4');
      expect(ep3.fgTotalMs, 123456);
      expect(ep3.hasFgDuration, isTrue);
      expect(ep4.fgTotalMs, isNull);
      expect(ep4.hasFgDuration, isFalse);
      expect(ep4.displayName, 'Ep04.mp4');
    });

    test('listTimelines groups every segment under its fg', () async {
      await repo.saveTimeline(
        storageId: 'local',
        path: 'Anime/Ep01.mp4',
        fgTotalMs: 600000,
        segments: [play(3000, 4000), play(0, 1000)],
      );
      await repo.saveTimeline(
        storageId: 'local',
        path: 'Anime/Ep02.mp4',
        fgTotalMs: 500000,
        segments: [play(0, 1000)],
      );

      final timelines = await repo.listTimelines();
      expect(timelines, hasLength(2));
      final ep1 = timelines.firstWhere((t) => t.path == 'Anime/Ep01.mp4');
      expect(ep1.segments, hasLength(2));
      expect(ep1.segments.map((s) => s.fgStartMs), [0, 3000]);
    });
  });

  group('replaceBgKeepingSpan', () {
    test('keeps fg placement and offset, swaps file and recomputes norms',
        () async {
      final original = MappingSegment(
        id: 7,
        action: MappingAction.playMedia,
        fgStartMs: 10000,
        fgEndMs: 40000,
        fgStartN: 1 / 60,
        fgEndN: 4 / 60,
        bgStorageId: 'local',
        bgPath: 'Anime/old.mp4',
        bgStartMs: 20000,
        bgEndMs: 50000,
        bgStartN: 2 / 60,
        bgEndN: 5 / 60,
        adjustedRate: 1.0,
      );

      final swapped = MappingBinding.replaceBgKeepingSpan(
        original,
        bgStorageId: 'local',
        bgPath: 'Anime/new.mp4',
        bgTotalMs: 200000,
      );

      expect(swapped.fgStartMs, 10000);
      expect(swapped.fgEndMs, 40000);
      // Offset (bgStart - fgStart) is unchanged: 20000 - 10000 = 10000.
      expect(swapped.bgStartMs, 20000);
      expect(swapped.bgEndMs, 50000);
      expect(swapped.bgStorageId, 'local');
      expect(swapped.bgPath, 'Anime/new.mp4');
      expect(swapped.bgStartN, closeTo(20000 / 200000, 1e-9));
      expect(swapped.bgEndN, closeTo(50000 / 200000, 1e-9));
      // Foreground placement fields are byte-for-byte identical.
      expect(swapped.fgStartN, original.fgStartN);
      expect(swapped.fgEndN, original.fgEndN);
    });

    test('unknown new duration clears the normalized bg fields', () {
      final original = play(0, 30000);
      final swapped = MappingBinding.replaceBgKeepingSpan(
        original,
        bgStorageId: 'local',
        bgPath: 'Anime/new.mp4',
      );
      expect(swapped.bgStartN, isNull);
      expect(swapped.bgEndN, isNull);
      // Window is re-derived from the UNCHANGED offset (1000), so it spans the
      // whole fg window (0..30000) at that offset rather than keeping the old
      // bg length — that is exactly the position/binding decoupling.
      expect(swapped.bgStartMs, 1000);
      expect(swapped.bgEndMs, 31000);
    });
  });

  group('runtime overflow guard', () {
    MappingSegment seg({double? startN, double? endN}) => MappingSegment(
          action: MappingAction.playMedia,
          fgStartMs: 0,
          fgEndMs: 60000,
          bgStorageId: 'local',
          bgPath: 'Anime/old.mp4',
          bgStartMs: 0,
          bgEndMs: 60000,
          bgStartN: startN,
          bgEndN: endN,
          adjustedRate: 1.0,
        );

    test('recovers the bg duration snapshot from normalized fields', () {
      final s = seg(endN: 60000 / 30000); // saved against a 30s bg
      expect(MappingTimelineMath.bgTotalMsFromNorms(s), 30000);
    });

    test('effective window truncates a window longer than its file', () {
      final s = seg(endN: 60000 / 30000); // 30s file, 60s window
      final w = MappingTimelineMath.effectiveBgWindow(s);
      expect(w.startMs, 0);
      expect(w.endMs, 30000);
      expect(w.covered, isTrue);
      expect(MappingTimelineMath.bgTargetMsFor(s, 60000), 30000);
      expect(MappingTimelineMath.segmentRate(s, 1.0), closeTo(0.5, 1e-9));
    });

    test('no coverage when the window starts past the file end', () {
      final s = MappingSegment(
        action: MappingAction.playMedia,
        fgStartMs: 0,
        fgEndMs: 60000,
        bgStorageId: 'local',
        bgPath: 'Anime/old.mp4',
        bgStartMs: 40000,
        bgEndMs: 60000,
        bgStartN: 40000 / 30000,
        bgEndN: 60000 / 30000,
      );
      final w = MappingTimelineMath.effectiveBgWindow(s);
      expect(w.covered, isFalse);
      expect(w.startMs, 40000);
      expect(w.endMs, 40000);
    });
  });
}
