import 'package:drift/drift.dart';
import 'package:iris/features/scenario_playback/model/db/tables/scenario_queue_builds_table.dart';
import 'package:iris/models/db/app_database.dart';

part 'scenario_queue_index_dao.g.dart';

/// One persisted list-row of a scenario's (or tag view's) effective queue.
///
/// A row is EITHER a single file ([mediaNodeId] set, [isGroup] false) OR a
/// merged virtual group ([groupId] set, [isGroup] true). [anchorRank] is the
/// element's position in the base order (for a group: the earliest member's),
/// which is the single seek key both row kinds share.
class QueueEntryRow {
  final int anchorRank;
  final bool isGroup;
  final String? groupId;
  final int? mediaNodeId;
  final int occurrenceIndex;
  final int flags;

  /// Identity of an UNAVAILABLE placeholder row (empty folder source, missing
  /// file-kind source, missing explicit item): such a row has no `media_nodes`
  /// row, so the read side rebuilds the greyed placeholder from these.
  final String? placeholderStorageId;
  final String? placeholderPath;

  const QueueEntryRow({
    required this.anchorRank,
    required this.isGroup,
    this.groupId,
    this.mediaNodeId,
    this.occurrenceIndex = 0,
    this.flags = 0,
    this.placeholderStorageId,
    this.placeholderPath,
  });

  /// True when this row marks a broken scope rather than a real file.
  bool get isPlaceholder =>
      !isGroup && (mediaNodeId == null || mediaNodeId! < 0);
}

/// One persisted member of a virtual group, in rule play order.
class GroupMemberRow {
  final int inGroupRank;
  final int mediaNodeId;
  final int occurrenceIndex;

  const GroupMemberRow({
    required this.inGroupRank,
    required this.mediaNodeId,
    this.occurrenceIndex = 0,
  });
}

/// One persisted virtual group (rule-dimension; shared by scenario + tag).
class GroupRow {
  final String groupId;
  final String ruleId;
  final String anchorRoot;
  final int displaySeq;
  final int segmentCount;
  final int totalDurationMs;
  final int totalSizeBytes;
  final List<GroupMemberRow> members;

  const GroupRow({
    required this.groupId,
    required this.ruleId,
    required this.anchorRoot,
    required this.displaySeq,
    required this.segmentCount,
    required this.totalDurationMs,
    required this.totalSizeBytes,
    required this.members,
  });
}

/// A group header joined to its FIRST and LAST still-present member — the
/// endpoints the read path treats as visible. Carries everything needed to
/// rebuild a group's display title and its representative row (title tags live
/// on the RULE, so the title is composed by the caller) WITHOUT materializing
/// the effective stream.
class GroupHeaderRow {
  final String groupId;
  final String ruleId;
  final String anchorRoot;
  final int displaySeq;
  final int segmentCount;
  final int totalDurationMs;

  /// First visible member's node identity + occurrence (the group's
  /// representative for playback).
  final int firstNodeId;
  final String firstStorageId;
  final String firstPath;
  final String? firstUri;
  final String? firstName;
  final int? firstWidth;
  final int? firstHeight;
  final int firstOccurrenceIndex;

  /// Last visible member's file name (the `lastFile` title tag).
  final String? lastName;

  const GroupHeaderRow({
    required this.groupId,
    required this.ruleId,
    required this.anchorRoot,
    required this.displaySeq,
    required this.segmentCount,
    required this.totalDurationMs,
    required this.firstNodeId,
    required this.firstStorageId,
    required this.firstPath,
    required this.firstUri,
    required this.firstName,
    required this.firstWidth,
    required this.firstHeight,
    required this.firstOccurrenceIndex,
    required this.lastName,
  });
}

/// The persisted BUILD META of a scenario's derived queue index.
///
/// The index is a CACHE: it can always be recomputed from the scenario
/// definition + VM rules, so eviction/rebuild is free to be aggressive.
///
/// The v39/v43 ROW tables (`scenario_queue_entries`, `vm_groups`,
/// `vm_group_members`) are gone as of schema v45: the shared-order index is the
/// only persisted representation. What lives here is the meta row the read paths
/// resolve a generation through (`currentBuildId`) plus the `app_meta` bookkeeping
/// keys. The `QueueEntryRow` / `GroupRow` / `GroupMemberRow` / `GroupHeaderRow`
/// value types below stay — the plan builder, the shared-order codec and the row
/// overlay all speak them.
@DriftAccessor(tables: [ScenarioQueueBuildsTable])
class ScenarioQueueIndexDao extends DatabaseAccessor<AppDatabase>
    with _$ScenarioQueueIndexDaoMixin {
  ScenarioQueueIndexDao(super.db);

  /// `app_meta` key holding the stored content signature of [scenarioId]'s
  /// generation (written by the store; stripped of session-relative parts).
  static String signatureKey(String scenarioId) => 'queue_index_sig:$scenarioId';

  /// `app_meta` key holding [scenarioId]'s last-used stamp (LRU retention).
  static String usedKey(String scenarioId) => 'queue_index_used:$scenarioId';

  /// Highest `build_id` currently stored for [scenarioId], or 0 when none.
  ///
  /// Reads `scenario_queue_builds` (PK `(scenario_id, build_id)`), so MAX is an
  /// O(1) index probe rather than a scan of the generation it describes.
  Future<int> currentBuildId(String scenarioId) async {
    final row = await customSelect(
      'SELECT MAX(build_id) AS b FROM scenario_queue_builds WHERE scenario_id = ?',
      variables: [Variable.withString(scenarioId)],
    ).getSingleOrNull();
    return row?.read<int?>('b') ?? 0;
  }

  /// Allocates a globally-unique build id.
  ///
  /// A generation is identified by its build id ALONE (the 36-char scenario id
  /// is no longer carried on every row/index), so two scenarios built in the
  /// same microsecond must not collide: the id is `max(now, highest + 1)`.
  Future<int> nextBuildId() async {
    final row = await customSelect(
      'SELECT MAX(build_id) AS b FROM scenario_queue_builds',
    ).getSingleOrNull();
    final maxExisting = row?.read<int?>('b') ?? 0;
    final now = DateTime.now().microsecondsSinceEpoch;
    return now > maxExisting ? now : maxExisting + 1;
  }

  /// Every scenario that currently has a materialized generation on disk.
  ///
  /// Backs the retention cap: the store keeps only the most-recently-used few
  /// so derived storage stays bounded however many scenarios exist.
  Future<List<String>> materializedScenarioIds() async {
    final rows = await customSelect(
      'SELECT DISTINCT scenario_id AS s FROM scenario_queue_builds',
    ).get();
    return [for (final r in rows) r.read<String>('s')];
  }

  /// Base file count (= the queue's index space / `totalItems`) for a
  /// generation, or null when the build meta row is missing (a stale or
  /// concurrently-evicted generation).
  ///
  /// Callers must decide the fallback themselves: a silent 0 here would make a
  /// racing read report an EMPTY queue.
  Future<int?> visibleBaseCount(String scenarioId, int buildId) async {
    final row = await customSelect(
      'SELECT base_count FROM scenario_queue_builds '
      'WHERE scenario_id = ? AND build_id = ?',
      variables: [Variable.withString(scenarioId), Variable.withInt(buildId)],
    ).getSingleOrNull();
    return row?.read<int>('base_count');
  }

  /// Records the generation's counts (base file count + visible row count).
  Future<void> writeBuildMeta({
    required String scenarioId,
    required int buildId,
    required int baseCount,
    required int entryCount,
  }) {
    return customInsert(
      'INSERT OR REPLACE INTO scenario_queue_builds '
      '(scenario_id, build_id, base_count, entry_count, built_at) '
      'VALUES (?, ?, ?, ?, ?)',
      variables: [
        Variable.withString(scenarioId),
        Variable.withInt(buildId),
        Variable.withInt(baseCount),
        Variable.withInt(entryCount),
        Variable.withInt(DateTime.now().millisecondsSinceEpoch),
      ],
    );
  }

  /// Deletes every build-meta row of [scenarioId] EXCEPT [keepBuildId].
  ///
  /// The generation IS the meta row (the rows it describes are gone as of v45),
  /// so dropping the other scenarios' entries here is what makes the shared
  /// index's `gcStaleGenerations` collect their blobs.
  Future<void> evictOtherBuilds(String scenarioId, int keepBuildId) async {
    await (delete(scenarioQueueBuildsTable)
          ..where((t) =>
              t.scenarioId.equals(scenarioId) &
              t.buildId.equals(keepBuildId).not()))
        .go();
  }

  /// Drops a scenario's generation (invalidation on definition change / scenario
  /// delete), together with the cross-restart `app_meta` bookkeeping keys the
  /// store wrote for it — so a deleted or evicted scenario leaves no orphan key
  /// pair behind.
  Future<void> clearScenario(String scenarioId) async {
    await (delete(scenarioQueueBuildsTable)
          ..where((t) => t.scenarioId.equals(scenarioId)))
        .go();
    await customUpdate(
      'DELETE FROM app_meta WHERE key = ? OR key = ?',
      variables: [
        Variable.withString(signatureKey(scenarioId)),
        Variable.withString(usedKey(scenarioId)),
      ],
    );
  }
}
