import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/db/dao/for_page/media_node_page_result.dart';
import 'package:iris/features/media_library/model/db/dao/media_nodes_dao.dart';
import 'package:iris/features/media_library/model/db/repositories/sub/media_node_repository.dart';
import 'package:iris/features/media_library/model/enum/media_lib_sources.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/media_library/search/model/search_exclude_rule.dart';
import 'package:iris/features/scenario_playback/model/enum/exclude_rule_kind.dart';
import 'package:iris/features/scenario_playback/model/enum/exclude_scope.dart';
import 'package:iris/models/db/app_database.dart';

void main() {
  late AppDatabase db;
  late MediaNodesDao dao;
  late MediaNodeRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dao = MediaNodesDao(db);
    repo = MediaNodeRepository(dao);
  });

  tearDown(() => db.close());

  Future<void> file(String storageId, String p) {
    final segments = p.split('/');
    return dao.insertNode(MediaNode.file(
      id: 'f:$storageId:$p',
      storageId: storageId,
      path: segments,
      name: segments.last,
      mediaType: MediaType.video,
    ));
  }

  List<String> names(MediaNodePageResult r) => r.items.map((e) => e.name).toList();

  SourcesQuerySource storageSrc(String storageId) =>
      (storageId: storageId, path: null, kind: MediaSourceKind.storage,
          recursive: true, scenarioSourceId: null);

  group('searchQuery token predicate (F-006)', () {
    setUp(() async {
      await file('st1', 'movie1.mp4');
      await file('st1', 'movie2.mp4');
      await file('st1', 'tvshow.mp4');
    });

    test('multiple tokens must ALL match (AND)', () async {
      final all = await repo.getPagedNodesForSources(
        sources: [storageSrc('st1')],
        searchQuery: 'movie 1',
        page: 1,
        pageSize: 100,
      );
      expect(names(all), ['movie1.mp4']);
    });

    test('single token substring, case-insensitive', () async {
      final all = await repo.getPagedNodesForSources(
        sources: [storageSrc('st1')],
        searchQuery: 'MOVIE',
        page: 1,
        pageSize: 100,
      );
      expect(names(all).toSet(), {'movie1.mp4', 'movie2.mp4'});
    });

    test('% and _ are literals, not wildcards (ESCAPE)', () async {
      await file('st1', '100%_done.mp4');
      await file('st1', 'movie0x.mp4');
      final q = await repo.getPagedNodesForSources(
        sources: [storageSrc('st1')],
        searchQuery: '0%_',
        page: 1,
        pageSize: 100,
      );
      // '0%_' as literals only matches the literal '0%_' substring → done.
      expect(names(q), ['100%_done.mp4']);
    });
  });

  group('per-source recursive vs direct (C3 / v5-D5)', () {
    setUp(() async {
      await file('st1', 'a/b1.mp4');
      await file('st1', 'a/b/b2.mp4');
      await file('st1', 'c/c1.mp4');
    });

    test('directory recursive covers the subtree', () async {
      final r = await repo.getPagedNodesForSources(
        sources: [
          (storageId: 'st1', path: 'a', kind: MediaSourceKind.directory,
              recursive: true, scenarioSourceId: null),
        ],
        page: 1,
        pageSize: 100,
      );
      expect(names(r).toSet(), {'b1.mp4', 'b2.mp4'});
    });

    test('directory non-recursive covers direct children only', () async {
      final r = await repo.getPagedNodesForSources(
        sources: [
          (storageId: 'st1', path: 'a', kind: MediaSourceKind.directory,
              recursive: false, scenarioSourceId: null),
        ],
        page: 1,
        pageSize: 100,
      );
      expect(names(r), ['b1.mp4']);
    });

    test('directory non-recursive at storage root = parentPath IS NULL',
        () async {
      await file('st1', 'root.mp4');
      final r = await repo.getPagedNodesForSources(
        sources: [
          (storageId: 'st1', path: '', kind: MediaSourceKind.directory,
              recursive: false, scenarioSourceId: null),
        ],
        page: 1,
        pageSize: 100,
      );
      expect(names(r), ['root.mp4']);
    });
  });

  group('exclude rules per source branch (v5-D3)', () {
    setUp(() async {
      await file('st1', 'a/x.mp4');
      await file('st1', 'a/b/deep.mp4');
      await file('st1', 'c/y.mp4');
    });

    test('scenario-scoped rule applies to every branch', () async {
      final r = await repo.getPagedNodesForSources(
        sources: [storageSrc('st1')],
        excludeRules: [
          SearchExcludeRule(
            scope: ExcludeScope.scenario,
            kind: ExcludeRuleKind.directory,
            storageId: 'st1',
            path: 'a',
            recursive: true,
          ),
        ],
        page: 1,
        pageSize: 100,
      );
      expect(names(r).toSet(), {'y.mp4'});
    });

    test('source-scoped rule prunes only its owning branch', () async {
      // X=/a recursive (sourceId 1) + Y=/a/b recursive (sourceId 2).
      final sources = [
        (storageId: 'st1', path: 'a', kind: MediaSourceKind.directory,
            recursive: true, scenarioSourceId: 1),
        (storageId: 'st1', path: 'a/b', kind: MediaSourceKind.directory,
            recursive: true, scenarioSourceId: 2),
      ];
      final r = await repo.getPagedNodesForSources(
        sources: sources,
        excludeRules: [
          SearchExcludeRule(
            scope: ExcludeScope.source,
            sourceId: 1,
            kind: ExcludeRuleKind.directory,
            storageId: 'st1',
            path: 'a/b',
            recursive: true,
          ),
        ],
        page: 1,
        pageSize: 100,
      );
      // X branch prunes /a/b (ancestor+exclude), but Y still returns deep.mp4.
      expect(names(r).toSet(), {'x.mp4', 'deep.mp4'});
    });

    test('synthetic current-dir tuple never carries source-scoped rules',
        () async {
      final r = await repo.getPagedNodesForSources(
        sources: [
          (storageId: 'st1', path: 'a', kind: MediaSourceKind.directory,
              recursive: true, scenarioSourceId: null),
        ],
        excludeRules: [
          SearchExcludeRule(
            scope: ExcludeScope.source,
            sourceId: 99,
            kind: ExcludeRuleKind.directory,
            storageId: 'st1',
            path: 'a',
            recursive: true,
          ),
        ],
        page: 1,
        pageSize: 100,
      );
      expect(names(r).toSet(), {'x.mp4', 'deep.mp4'});
    });

    test('empty sources returns empty page (safe)', () async {
      final r = await repo.getPagedNodesForSources(sources: const [], page: 1);
      expect(r.totalItems, 0);
      expect(r.items, isEmpty);
    });
  });

  group('getExistingFilePaths (v4-D2)', () {
    test('returns canonical paths of present file rows', () async {
      await file('st1', 'a/x.mp4');
      final found = await repo.getExistingFilePaths(
        storageId: 'st1',
        paths: ['a/x.mp4', 'a/y.mp4'],
      );
      expect(found, {'a/x.mp4'});
    });

    test('ignores directory rows and other storages', () async {
      await file('st2', 'a/x.mp4');
      final found = await repo.getExistingFilePaths(
        storageId: 'st1',
        paths: ['a/x.mp4'],
      );
      expect(found, isEmpty);
    });
  });
}
