import 'package:drift/drift.dart';
import 'package:iris/features/tag_play/model/db/adapters/tag_play_member_adapter.dart';
import 'package:iris/features/tag_play/model/db/tables/video_tag_members_table.dart';
import 'package:iris/features/tag_play/model/domain/tag_play_member.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/storage_path_codec.dart';
import 'package:iris/models/db/storage_scope.dart';
import 'package:iris/utils/path_conv.dart';
import 'package:iris/utils/path_prefix_remap.dart';

part 'video_tag_members_dao.g.dart';

@DriftAccessor(tables: [VideoTagMembersTable])
class VideoTagMembersDao extends DatabaseAccessor<AppDatabase>
    with _$VideoTagMembersDaoMixin {
  VideoTagMembersDao(super.db);

  /// All raw membership rows of [tagId] (expiry filtering happens at the
  /// repository layer where the tag's retention window is known).
  Future<List<TagPlayMember>> membersOf(int tagId) async {
    final rows = await (select(videoTagMembersTable)
          ..where((t) => t.tagId.equals(tagId))
          ..orderBy([
            (t) => OrderingTerm(
                  expression: t.addedAt,
                  mode: OrderingMode.desc,
                )
          ]))
        .get();
    return rows.map(TagPlayMemberAdapter.fromDb).toList(growable: false);
  }

  /// Every membership row across all tags (newest first). One query for the
  /// sheet's per-row media counts instead of N per-tag reads.
  Future<List<TagPlayMember>> allMembers() async {
    final rows = await (select(videoTagMembersTable)
          ..orderBy([
            (t) => OrderingTerm(
                  expression: t.addedAt,
                  mode: OrderingMode.desc,
                )
          ]))
        .get();
    return rows.map(TagPlayMemberAdapter.fromDb).toList(growable: false);
  }

  /// Media node ids that [tagId]'s members resolve to, with the optional
  /// [addedAfter] cutoff applied to the MEMBER row.
  ///
  /// The shared-order tag reads address members by NODE ID (the derived index
  /// stores node ids, not paths), so the membership rows are resolved against
  /// `media_nodes` here instead of being looked up one at a time.
  Future<List<int>> memberNodeIds(int tagId, {DateTime? addedAfter}) async {
    final members = await _members(tagId: tagId, addedAfter: addedAfter);
    final ids = await _resolveNodeIds(members);
    return [for (final id in ids) if (id != null) id];
  }

  /// Every tag's member node ids in one pass, as `(tagId, nodeId)` pairs, with
  /// the optional [addedAfter] cutoff applied to the MEMBER rows.
  ///
  /// The shared intersection count needs `nodeId → tagIds` to walk the index
  /// once; resolving every membership in one batch beats a query per tag.
  Future<List<({int tagId, int nodeId})>> memberNodeIdsByTag(
      {DateTime? addedAfter}) async {
    final members = await _members(addedAfter: addedAfter);
    final ids = await _resolveNodeIds(members);
    return [
      for (var i = 0; i < members.length; i++)
        if (ids[i] != null) (tagId: members[i].tagId, nodeId: ids[i]!),
    ];
  }

  /// Membership rows for the given filters (raw rows — expiry filtering stays
  /// a repository concern where the retention window is known).
  ///
  /// The [addedAfter] cutoff goes through Drift's typed DateTime expression,
  /// which applies the column's storage unit; a raw `added_at >= <ms>` binding
  /// compared unix SECONDS against milliseconds and matched nothing.
  Future<List<VideoTagMembersTableData>> _members({
    int? tagId,
    DateTime? addedAfter,
  }) {
    return (select(videoTagMembersTable)
          ..where((t) {
            Expression<bool> cond = const Constant(true);
            if (tagId != null) cond = cond & t.tagId.equals(tagId);
            if (addedAfter != null) {
              cond = cond & t.addedAt.isBiggerOrEqualValue(addedAfter);
            }
            return cond;
          }))
        .get();
  }

  /// Resolves membership rows to `media_nodes` ids (null = vanished file),
  /// aligned 1:1 with [members].
  ///
  /// The two tables store DIFFERENT PATH DOMAINS: `video_tag_members.path` is
  /// DOMAIN-absolute (`D:/Videos/a.mp4` — what the queue/resolver speak), while
  /// `media_nodes.path` is RELATIVE to the storage base since schema v38, so a
  /// raw `n.path = m.path` SQL join matched nothing once a base path was
  /// configured. Following the media-node convention ("canonicalize on the
  /// lookup side", see `MediaNodesDao.getByPath`), each member path is
  /// relativized here and probed by `(data_scope_id, path)` — nodes are keyed
  /// by SCOPE, not entry id, so linked entries find the shared library. The
  /// codec is idempotent: rows stored in either form resolve.
  Future<List<int?>> _resolveNodeIds(
      List<VideoTagMembersTableData> members) async {
    if (members.isEmpty) return const [];
    // Dedup the probes per scope: one batched IN() per scope, not one query
    // per member (a tag can carry thousands of rows).
    final probes = <String, Set<String>>{};
    final probeOf = <int, String>{};
    for (final m in members) {
      final scope = StorageScope.of(m.storageId);
      final rel =
          StoragePathCodec.relativize(m.storageId, canonicalDbPath(m.path));
      probeOf[m.id] = '$scope|$rel';
      probes.putIfAbsent(scope, () => <String>{}).add(rel);
    }
    final nodeIdByProbe = <String, int>{};
    const chunkSize = 900; // stay under SQLite's 999-variable limit
    for (final entry in probes.entries) {
      final paths = entry.value.toList(growable: false);
      for (var i = 0; i < paths.length; i += chunkSize) {
        final chunk = paths.sublist(
            i, i + chunkSize > paths.length ? paths.length : i + chunkSize);
        final rows = await (select(attachedDatabase.mediaNodesTable)
              ..where((t) =>
                  t.dataScopeId.equals(entry.key) & t.path.isIn(chunk)))
            .get();
        for (final r in rows) {
          nodeIdByProbe['${entry.key}|${r.path}'] = r.id;
        }
      }
    }
    return [for (final m in members) nodeIdByProbe[probeOf[m.id]]];
  }

  /// Newest membership row of [tagId], or null when the tag has none.
  Future<TagPlayMember?> latestOf(int tagId) async {
    final rows = await (select(videoTagMembersTable)
          ..where((t) => t.tagId.equals(tagId))
          ..orderBy([
            (t) => OrderingTerm(
                  expression: t.addedAt,
                  mode: OrderingMode.desc,
                )
          ])
          ..limit(1))
        .get();
    return rows.isEmpty ? null : TagPlayMemberAdapter.fromDb(rows.first);
  }

  /// Every membership row whose (storageId, canonicalPath) pair matches any of
  /// the given sets — the bulk lookup behind per-row tag chips in queue lists.
  Future<List<TagPlayMember>> membersMatching({
    required List<String> storageIds,
    required List<String> paths,
  }) async {
    if (storageIds.isEmpty || paths.isEmpty) return const [];
    final rows = await (select(videoTagMembersTable)
          ..where((t) => t.storageId.isIn(storageIds) & t.path.isIn(paths)))
        .get();
    return rows.map(TagPlayMemberAdapter.fromDb).toList(growable: false);
  }

  /// Membership counts per tag, in SQL, optionally ignoring members added
  /// before [addedAfter] (retention cutoff). One GROUP BY for the whole sheet.
  ///
  /// The cutoff uses Drift's typed DateTime expression for the same unit reason
  /// as [_members]: the column stores unix seconds, a raw millisecond binding
  /// counted nothing.
  Future<Map<int, int>> countsByTag({DateTime? addedAfter}) async {
    final countExpr = countAll();
    final query = selectOnly(videoTagMembersTable)
      ..addColumns([videoTagMembersTable.tagId, countExpr])
      ..groupBy([videoTagMembersTable.tagId]);
    if (addedAfter != null) {
      query.where(videoTagMembersTable.addedAt.isBiggerOrEqualValue(addedAfter));
    }
    final rows = await query.get();
    return {
      for (final r in rows)
        r.read(videoTagMembersTable.tagId)!: r.read(countExpr) ?? 0,
    };
  }

  /// Tag ids the given media currently belongs to.
  Future<List<int>> tagIdsOfMedia(String storageId, String canonicalPath) {
    return (select(videoTagMembersTable)
          ..where((t) =>
              t.storageId.equals(storageId) & t.path.equals(canonicalPath)))
        .get()
        .then((rows) => rows.map((r) => r.tagId).toList(growable: false));
  }

  /// Adds/refreshes a membership. Conflict on the (tag, storage, path) UNIQUE
  /// key refreshes `addedAt` (re-tagging), never duplicating rows.
  Future<void> addMember({
    required int tagId,
    required String storageId,
    required String canonicalPath,
    required DateTime addedAt,
  }) async {
    await into(videoTagMembersTable).insert(
      VideoTagMembersTableCompanion.insert(
        tagId: tagId,
        storageId: storageId,
        path: canonicalPath,
        addedAt: Value(addedAt),
      ),
      onConflict: DoUpdate(
        (old) => VideoTagMembersTableCompanion(addedAt: Value(addedAt)),
        target: [
          videoTagMembersTable.tagId,
          videoTagMembersTable.storageId,
          videoTagMembersTable.path,
        ],
      ),
    );
  }

  Future<int> removeMember({
    required int tagId,
    required String storageId,
    required String canonicalPath,
  }) {
    return (delete(videoTagMembersTable)
          ..where((t) =>
              t.tagId.equals(tagId) &
              t.storageId.equals(storageId) &
              t.path.equals(canonicalPath)))
        .go();
  }

  Future<int> removeAllMembersOfTag(int tagId) {
    return (delete(videoTagMembersTable)..where((t) => t.tagId.equals(tagId)))
        .go();
  }

  /// Deletes every member of [tagId] added before [cutoff]. Returns removed
  /// row count. This is the retention sweep's inner step (per-tag cutoff).
  Future<int> deleteExpiredOfTag(int tagId, DateTime cutoff) {
    return (delete(videoTagMembersTable)
          ..where((t) =>
              t.tagId.equals(tagId) & t.addedAt.isSmallerThanValue(cutoff)))
        .go();
  }

  /// Rewrites the leading [oldBase] of every membership path for [storageId] to
  /// [newBase] (drive-letter reassignment).
  Future<int> remapPathPrefix({
    required String storageId,
    required String oldBase,
    required String newBase,
  }) {
    final query = buildPathPrefixRemap(
      table: 'video_tag_members',
      keyColumn: 'storage_id',
      keyValue: storageId,
      oldBase: oldBase,
      newBase: newBase,
    );
    return customUpdate(
      query.sql,
      variables: query.variables,
      updates: {videoTagMembersTable},
    );
  }
}
