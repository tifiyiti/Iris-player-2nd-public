import 'dart:typed_data';

import 'package:iris/features/media_library/model/db/dao/for_page/media_node_page_query.dart';
import 'package:iris/features/media_library/model/db/repositories/sub/media_node_repository.dart';
import 'package:iris/features/media_library/model/enum/basic_enum.dart';
import 'package:iris/features/media_library/model/enum/media_node.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/scenario_playback/model/enum/scenario_sort_field.dart';

/// A shared, scenario-independent ORDER over one media scope.
///
/// The v43 derived index persists a per-scenario permutation of node ids —
/// twice (queue rows and VM group members). With many whole-library scenarios
/// that is largely the SAME permutation stored N times. A shared order is built
/// once per (scope, sort, direction, grouping, media-type set) and each scenario
/// then stores only a membership bitmap over it; a scenario's base order is the
/// concatenation of its sources, each a FILTERED SUBSEQUENCE of this order
/// (filtering an ordered set preserves order).
///
/// The order is produced through the SAME query the folder source provider uses
/// ([MediaNodeRepository.getPagedNodes] with `matchAllInStorage`), so it cannot
/// drift from the order the resolver sees (tie-breaks, NULL-last rules, index
/// plan all match by construction).
class SharedMediaOrder {
  const SharedMediaOrder._();

  /// Rows fetched per round trip while building; bounds peak memory on a 500k
  /// scope without materializing one giant result set.
  static const int buildChunk = 20000;

  /// Stable key for one order. Every input that affects the row set or the
  /// ORDER BY is part of it, so two callers with the same key must get the same
  /// sequence. The `vN` prefix is the ORDER FORMAT version: bump it whenever the
  /// ORDER BY semantics change, so an order persisted under the old rules is
  /// rebuilt instead of reused.
  static String orderKey({
    required String storageId,
    required ScenarioSortField sortField,
    required SortDirection sortDirection,
    required bool pathGroupFirst,
    required List<MediaType> mediaTypes,
  }) {
    // v2: the ORDER BY gained a deterministic name/path tail and NULLs-last on
    // both query paths, and modified_at became milliseconds — so a v1 sequence
    // is no longer the same order.
    final types = mediaTypes.map((e) => e.name).toList()..sort();
    return 'v2|$storageId|${sortField.name}|${sortDirection.name}'
        '|${pathGroupFirst ? 'g' : 'f'}|${types.join(',')}';
  }

  /// The full ordered node-id sequence of [storageId] under [sortField].
  ///
  /// Throws [StateError] if a node id does not fit int32 — the packed order
  /// format is int32, and a silent wrap would corrupt every rank.
  static Future<Int32List> build(
    MediaNodeRepository nodeRepo, {
    required String storageId,
    required ScenarioSortField sortField,
    required SortDirection sortDirection,
    required bool pathGroupFirst,
    required List<MediaType> mediaTypes,
    int chunk = buildChunk,
  }) async {
    final ids = <int>[];
    var page = 1;
    while (true) {
      final result = await nodeRepo.getPagedNodes(MediaNodePageQuery(
        page: page,
        pageSize: chunk,
        storageId: storageId,
        nodeKind: MediaNodeKind.file,
        mediaTypes: mediaTypes,
        matchAllInStorage: true,
        sortField: sortField.toMediaSortField(),
        sortDirection: sortDirection,
        pathGroupFirst: pathGroupFirst,
        countTotal: false,
      ));
      if (result.items.isEmpty) break;
      for (final node in result.items) {
        final id = int.tryParse(node.id);
        if (id == null || id > 0x7fffffff) {
          throw StateError('media node id "${node.id}" does not fit int32');
        }
        ids.add(id);
      }
      if (result.items.length < chunk) break;
      page++;
    }
    return Int32List.fromList(ids);
  }
}
