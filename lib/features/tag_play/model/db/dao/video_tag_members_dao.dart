import 'package:drift/drift.dart';
import 'package:iris/features/tag_play/model/db/adapters/tag_play_member_adapter.dart';
import 'package:iris/features/tag_play/model/db/tables/video_tag_members_table.dart';
import 'package:iris/features/tag_play/model/domain/tag_play_member.dart';
import 'package:iris/models/db/app_database.dart';
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

  /// Builds the `WHERE` clause from [clauses], so no caller has to hand-assemble
  /// a leading `WHERE` vs a continuing `AND` (the two tag lookups below differ
  /// only in whether they have an extra leading filter).
  static String _where(List<String> clauses) =>
      clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}';

  /// Media node ids that [tagId]'s members resolve to, with the optional
  /// [addedAfter] cutoff applied to the MEMBER row.
  ///
  /// The shared-order tag reads address members by NODE ID (the derived index
  /// stores node ids, not paths), so the `(storageId, path)` membership rows are
  /// joined to `media_nodes` here instead of being looked up one at a time.
  Future<List<int>> memberNodeIds(int tagId, {DateTime? addedAfter}) async {
    final rows = await customSelect(
      'SELECT n.id AS node_id FROM video_tag_members m '
      'JOIN media_nodes n ON n.storage_id = m.storage_id AND n.path = m.path '
      '${_where([
        'm.tag_id = ?',
        if (addedAfter != null) 'm.added_at >= ?',
      ])}',
      variables: [
        Variable.withInt(tagId),
        if (addedAfter != null)
          Variable.withInt(addedAfter.millisecondsSinceEpoch),
      ],
    ).get();
    return [for (final r in rows) r.read<int>('node_id')];
  }

  /// Every tag's member node ids in one pass, as `(tagId, nodeId)` pairs, with
  /// the optional [addedAfter] cutoff applied to the MEMBER rows.
  ///
  /// The shared intersection count needs `nodeId → tagIds` to walk the index
  /// once; one join beats a query per tag.
  Future<List<({int tagId, int nodeId})>> memberNodeIdsByTag(
      {DateTime? addedAfter}) async {
    final rows = await customSelect(
      'SELECT m.tag_id AS tag_id, n.id AS node_id FROM video_tag_members m '
      'JOIN media_nodes n ON n.storage_id = m.storage_id AND n.path = m.path '
      '${_where([
        if (addedAfter != null) 'm.added_at >= ?',
      ])}',
      variables: [
        if (addedAfter != null)
          Variable.withInt(addedAfter.millisecondsSinceEpoch),
      ],
    ).get();
    return [
      for (final r in rows)
        (tagId: r.read<int>('tag_id'), nodeId: r.read<int>('node_id')),
    ];
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
  Future<Map<int, int>> countsByTag({DateTime? addedAfter}) async {
    final where = addedAfter == null ? '' : 'WHERE added_at >= ?';
    final rows = await customSelect(
      'SELECT tag_id, COUNT(*) AS c FROM video_tag_members $where GROUP BY tag_id',
      variables: [
        if (addedAfter != null)
          Variable.withInt(addedAfter.millisecondsSinceEpoch),
      ],
    ).get();
    return {
      for (final r in rows) r.read<int>('tag_id'): r.read<int>('c'),
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
