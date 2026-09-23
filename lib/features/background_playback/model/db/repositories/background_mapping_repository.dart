import 'package:drift/drift.dart';
import 'package:iris/features/background_playback/model/db/dao/bg_mapping_segments_dao.dart';
import 'package:iris/features/background_playback/model/db/dao/bg_mappings_dao.dart';
import 'package:iris/features/background_playback/model/domain/background_mapping.dart';
import 'package:iris/features/background_playback/model/domain/background_mapping_summary.dart';
import 'package:iris/features/background_playback/model/enum/mapping_action.dart';
import 'package:iris/features/media_library/model/db/dao/media_nodes_dao.dart';
import 'package:iris/features/media_library/model/db/repositories/sub/media_node_repository.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/utils/path_conv.dart' show canonicalDbPath, canonicalKey;

/// Thrown when a timeline violates the non-overlap / bounds contract. UI
/// flows (segment editor) pre-empt these with choice dialogs; this is the
/// repository-level last line of defense so a bad write can never land.
class MappingValidationError implements Exception {
  MappingValidationError(this.message);
  final String message;

  @override
  String toString() => 'MappingValidationError: $message';
}

/// v26 mapping timeline persistence — one timeline per foreground
/// (storage_id, canonical path); segments replace atomically per save.
class BackgroundMappingRepository {
  BackgroundMappingRepository({
    required BgMappingsDao mappingsDao,
    required BgMappingSegmentsDao segmentsDao,
    required AppDatabase db,
    MediaNodeRepository? nodeRepo,
  })  : _mappingsDao = mappingsDao,
        _segmentsDao = segmentsDao,
        _db = db,
        _nodeRepo = nodeRepo ?? MediaNodeRepository(MediaNodesDao(db));

  final BgMappingsDao _mappingsDao;
  final BgMappingSegmentsDao _segmentsDao;
  final AppDatabase _db;
  final MediaNodeRepository _nodeRepo;

  /// Loads the whole timeline for the foreground file (null when unmapped).
  Future<BackgroundMappingTimeline?> getTimelineForFg({
    required String storageId,
    required String path,
  }) async {
    final row = await _mappingsDao.getByFg(
      storageId: storageId,
      path: canonicalDbPath(path),
    );
    if (row == null) return null;
    final segmentRows = await _segmentsDao.getForMapping(row.id);
    return BackgroundMappingTimeline(
      storageId: row.storageId,
      path: row.path,
      fgTotalMs: row.fgTotalMs,
      updatedAt: row.updatedAt,
      segments: [
        for (final s in segmentRows) _segmentFromRow(s),
      ],
    );
  }

  /// Whether the foreground file has a non-empty saved 副音 pairing — the
  /// "smart" 作用范围 / "已保存副音 fg 自动播放" trigger. An empty timeline does
  /// not count (nothing to play).
  Future<bool> hasTimelineFor({
    required String storageId,
    required String path,
  }) async {
    if (storageId.isEmpty || path.isEmpty) return false;
    final row = await _mappingsDao.getByFg(
      storageId: storageId,
      path: canonicalDbPath(path),
    );
    if (row == null) return false;
    final segmentRows = await _segmentsDao.getForMapping(row.id);
    return segmentRows.isNotEmpty;
  }

  /// Every timeline in the database as a light Level-1 summary row, newest
  /// edit first. Foreground duration comes from the saved snapshot and falls
  /// back to the scanned `media_nodes.duration_ms`; a still-null duration marks
  /// the row unavailable for the manager (the feature is disabled for it).
  ///
  /// Node info resolves in ONE batched lookup (the per-row probe was N+1);
  /// rows the batch misses still fall back to the legacy single probe (shared
  /// data-scope edge), so the output is identical.
  Future<List<BackgroundMappingSummary>> listSummaries() async {
    final mappings = await _mappingsDao.getAll();
    if (mappings.isEmpty) return const <BackgroundMappingSummary>[];

    final segments = await _segmentsDao.getAll();
    final counts = <int, int>{};
    final bgNames = <int, Set<String>>{};
    for (final s in segments) {
      counts[s.mappingId] = (counts[s.mappingId] ?? 0) + 1;
      final p = s.bgPath;
      if (p != null && p.isNotEmpty) {
        (bgNames[s.mappingId] ??= <String>{}).add(_baseName(p));
      }
    }

    final batchByKey = <String, ({String? name, int? durationMs})>{};
    try {
      final nodes = await _nodeRepo.nodesByMediaKeys(
        {for (final m in mappings) canonicalKey(m.storageId, m.path)},
      );
      for (final n in nodes) {
        final f = n.maybeMap(file: (v) => v, orElse: () => null);
        if (f == null) continue;
        batchByKey[canonicalKey(f.storageId, f.path.join('/'))] =
            (name: f.name, durationMs: f.durationMs);
      }
    } catch (_) {
      // A batch failure must not break the list; every row falls back below.
    }

    final out = <BackgroundMappingSummary>[];
    for (final m in mappings) {
      final node = batchByKey[canonicalKey(m.storageId, m.path)] ??
          await _fgNodeInfo(m.storageId, m.path);
      final names = (bgNames[m.id]?.toList() ?? <String>[])..sort();
      out.add(BackgroundMappingSummary(
        storageId: m.storageId,
        path: m.path,
        mediaId: m.mediaId,
        fgTotalMs: m.fgTotalMs ?? node.durationMs,
        updatedAt: m.updatedAt,
        segmentCount: counts[m.id] ?? 0,
        bgNames: names,
        fgName: node.name,
      ));
    }
    return out;
  }

  /// Every timeline with its full segment list, newest edit first — the
  /// manager's Level-2/editor source. Grouped in one pass (no N+1).
  Future<List<BackgroundMappingTimeline>> listTimelines() async {
    final mappings = await _mappingsDao.getAll();
    if (mappings.isEmpty) return const <BackgroundMappingTimeline>[];

    final segments = await _segmentsDao.getAll();
    final byMapping = <int, List<MappingSegment>>{};
    for (final r in segments) {
      (byMapping[r.mappingId] ??= <MappingSegment>[]).add(_segmentFromRow(r));
    }
    return [
      for (final m in mappings)
        BackgroundMappingTimeline(
          storageId: m.storageId,
          path: m.path,
          fgTotalMs: m.fgTotalMs,
          updatedAt: m.updatedAt,
          segments: byMapping[m.id] ?? const <MappingSegment>[],
        ),
    ];
  }

  /// Scanned node info for a foreground file: display name + probed duration.
  Future<({String? name, int? durationMs})> _fgNodeInfo(
    String storageId,
    String path,
  ) async {
    final row = await (_db.select(_db.mediaNodesTable)
          ..where((t) =>
              t.path.equals(path) &
              (t.storageId.equals(storageId) |
                  t.dataScopeId.equals(storageId)))
          ..limit(1))
        .getSingleOrNull();
    return (name: row?.name, durationMs: row?.durationMs);
  }

  static String _baseName(String p) {
    final i = p.lastIndexOf('/');
    return i < 0 ? p : p.substring(i + 1);
  }

  /// Atomically replaces the timeline of [storageId]/[path] with [segments]
  /// (insert-or-update the parent row first). The caller (editor) is expected
  /// to resolve overlaps through its choice dialog; this validates strictly.
  Future<void> saveTimeline({
    required String storageId,
    required String path,
    int? mediaId,
    int? fgTotalMs,
    required List<MappingSegment> segments,
  }) async {
    final canonical = canonicalDbPath(path);
    if (storageId.isEmpty || canonical.isEmpty) {
      throw MappingValidationError('empty fg identity');
    }
    _validateSegments(segments);

    await _db.transaction(() async {
      final existing = await _mappingsDao.getByFg(
        storageId: storageId,
        path: canonical,
      );
      final mappingId = existing?.id ??
          await _mappingsDao.insertRow(
            storageId: storageId,
            path: canonical,
            mediaId: mediaId,
            fgTotalMs: fgTotalMs,
          );
      if (existing != null) {
        await _mappingsDao.updateTotalAndMedia(
          mappingId,
          mediaId: mediaId,
          fgTotalMs: fgTotalMs,
        );
      }
      await _segmentsDao.deleteForMapping(mappingId);
      for (final s in segments) {
        await _segmentsDao.insertSegment(_segmentToCompanion(mappingId, s));
      }
    });
  }

  Future<void> deleteForFg({
    required String storageId,
    required String path,
  }) async {
    final row = await _mappingsDao.getByFg(
      storageId: storageId,
      path: canonicalDbPath(path),
    );
    if (row == null) return;
    await _mappingsDao.deleteRow(row.id); // cascade removes segments
  }

  // ── Validation & mapping ──

  void _validateSegments(List<MappingSegment> segments) {
    if (segments.isEmpty) return;
    for (final s in segments) {
      if (s.fgStartMs < 0 || s.fgEndMs <= s.fgStartMs) {
        throw MappingValidationError(
            'bad fg range ${s.fgStartMs}..${s.fgEndMs}');
      }
      if (s.activeSeq < 0) {
        throw MappingValidationError('negative activeSeq ${s.activeSeq}');
      }
      if (s.isPlayMedia) {
        if (s.bgStorageId == null ||
            s.bgStorageId!.isEmpty ||
            s.bgPath == null ||
            s.bgPath!.isEmpty) {
          throw MappingValidationError('playMedia requires a bg file');
        }
        final bs = s.bgStartMs ?? -1;
        final be = s.bgEndMs ?? -1;
        if (bs < 0 || be <= bs) {
          throw MappingValidationError('bad bg range $bs..$be');
        }
      } else {
        if (s.bgStorageId != null || s.bgPath != null) {
          throw MappingValidationError('silence must not carry a bg file');
        }
      }
    }
    // Overlaps are ALLOWED (v34): active segments resolve by activation order
    // (last-fired-wins, see `ActiveMappingResolver`), and disabled segments may
    // overlap anything. The per-segment range/identity checks above are the
    // remaining invariants.
  }

  /// Clamps a stored per-segment percent into 0..100; null stays null.
  static int? _clampPercent(int? v) => v?.clamp(0, 100);

  MappingSegment _segmentFromRow(BgMappingSegmentsTableData row) =>
      MappingSegment(
        id: row.id,
        action: row.action == MappingAction.silence.name
            ? MappingAction.silence
            : MappingAction.playMedia,
        fgStartMs: row.fgStartMs,
        fgEndMs: row.fgEndMs,
        fgStartN: row.fgStartN,
        fgEndN: row.fgEndN,
        bgStorageId: row.bgStorageId,
        bgPath: row.bgPath,
        bgStartMs: row.bgStartMs,
        bgEndMs: row.bgEndMs,
        bgStartN: row.bgStartN,
        bgEndN: row.bgEndN,
        adjustedRate: row.adjustedRate,
        fgPercent: row.fgPercent,
        bgPercent: row.bgPercent,
        colorArgb: row.colorArgb,
        isActive: row.isActive,
        activeSeq: row.activeSeq,
      );

  BgMappingSegmentsTableCompanion _segmentToCompanion(
    int mappingId,
    MappingSegment s,
  ) {
    return BgMappingSegmentsTableCompanion.insert(
      mappingId: mappingId,
      action: s.action.name,
      fgStartMs: s.fgStartMs,
      fgEndMs: s.fgEndMs,
      fgStartN: Value(s.fgStartN),
      fgEndN: Value(s.fgEndN),
      bgStorageId: Value(s.bgStorageId),
      bgPath: Value(s.bgPath == null ? null : canonicalDbPath(s.bgPath!)),
      bgStartMs: Value(s.bgStartMs),
      bgEndMs: Value(s.bgEndMs),
      bgStartN: Value(s.bgStartN),
      bgEndN: Value(s.bgEndN),
      adjustedRate: Value(s.adjustedRate),
      fgPercent: Value(_clampPercent(s.fgPercent)),
      bgPercent: Value(_clampPercent(s.bgPercent)),
      colorArgb: Value(s.colorArgb),
      isActive: Value(s.isActive),
      activeSeq: Value(s.activeSeq),
    );
  }
}
