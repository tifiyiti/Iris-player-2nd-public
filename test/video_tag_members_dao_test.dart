import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/db/dao/media_nodes_dao.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/tag_play/model/db/dao/video_tag_members_dao.dart';
import 'package:iris/features/tag_play/model/db/dao/video_tag_pin_presets_dao.dart';
import 'package:iris/features/tag_play/model/db/dao/video_tag_view_states_dao.dart';
import 'package:iris/features/tag_play/model/db/dao/video_tags_dao.dart';
import 'package:iris/features/tag_play/model/db/repositories/tag_play_repository.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/storage_path_codec.dart';
import 'package:iris/models/db/storage_scope.dart';

import 'helpers/sqlite3_loader.dart';

/// `memberNodeIds` / `memberNodeIdsByTag` join membership rows to
/// `media_nodes` by path, but the two tables store DIFFERENT DOMAINS since
/// schema v38: `media_nodes.path` is RELATIVE to the storage base path,
/// while `video_tag_members.path` stays DOMAIN-absolute. With a base path
/// configured (the normal case for local drives) a raw `n.path = m.path`
/// never matches — every tag view resolves empty while the (slow) walk
/// fallback would have found the members.
void main() {
  ensureSqlite3Loaded();

  late AppDatabase db;
  late TagPlayRepository repo;
  late MediaNodesDao nodesDao;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = TagPlayRepository(
      tagsDao: VideoTagsDao(db),
      membersDao: VideoTagMembersDao(db),
      viewStatesDao: VideoTagViewStatesDao(db),
      presetsDao: VideoTagPinPresetsDao(db),
      db: db,
    );
    nodesDao = MediaNodesDao(db);
    // Realistic production wiring: a local drive with a base path makes
    // `media_nodes` store RELATIVE paths while members stay absolute. `st2`
    // is the linked entry used by the shared-scope case (same base tree).
    StoragePathCodec.baseResolver = (id) =>
        (id == 'st1' || id == 'st2') ? const ['D:'] : null;
  });

  tearDown(() async {
    StoragePathCodec.baseResolver = (_) => null;
    StorageScope.reset();
    await db.close();
  });

  /// Inserts a file node with a DOMAIN-absolute path; the adapter relativizes
  /// it on the way in (as the scanner does), so the row ends up relative.
  Future<int> insertFile(String storageId, List<String> domainPath) {
    return nodesDao.insertNode(MediaNode.file(
      id: domainPath.join('/'),
      storageId: storageId,
      path: domainPath,
      name: domainPath.last,
      mediaType: MediaType.video,
    ));
  }

  group('member node id lookup across path domains', () {
    test('memberNodeIds joins absolute member paths to relative node paths',
        () async {
      final nodeId = await insertFile('st1', ['D:', 'Videos', '0001.mp4']);
      final tag = await repo.createTag(name: 't');
      await repo.addMember(
        tagId: tag.id,
        storageId: 'st1',
        pathSegments: ['D:/Videos/0001.mp4'],
      );

      expect(await VideoTagMembersDao(db).memberNodeIds(tag.id), [nodeId],
          reason: 'the member path must be canonicalized to the storage-base '
              'relative form on the lookup side, like every other path-keyed '
              'media_nodes accessor');
    });

    test('memberNodeIdsByTag resolves the same membership pairs', () async {
      final nodeId = await insertFile('st1', ['D:', 'Videos', '0002.mp4']);
      final tag = await repo.createTag(name: 't');
      await repo.addMember(
        tagId: tag.id,
        storageId: 'st1',
        pathSegments: ['D:/Videos/0002.mp4'],
      );

      final pairs = await VideoTagMembersDao(db).memberNodeIdsByTag();
      expect(pairs, [(tagId: tag.id, nodeId: nodeId)]);
    });

    test('a member whose file is gone resolves to no node id', () async {
      final tag = await repo.createTag(name: 't');
      await repo.addMember(
        tagId: tag.id,
        storageId: 'st1',
        pathSegments: ['D:/Videos/vanished.mp4'],
      );

      expect(await VideoTagMembersDao(db).memberNodeIds(tag.id), isEmpty);
    });

    test('member rows stored RELATIVE (legacy/remote) still resolve',
        () async {
      // storages without a base path never relativize, so both sides are
      // absolute — and a pre-v38-style row must keep working either way.
      final nodeId = await insertFile('webdav', ['Movies', 'a.mp4']);
      final tag = await repo.createTag(name: 't');
      await repo.addMember(
        tagId: tag.id,
        storageId: 'webdav',
        pathSegments: ['Movies/a.mp4'],
      );

      expect(await VideoTagMembersDao(db).memberNodeIds(tag.id), [nodeId]);
    });

    test('a shared data scope resolves members across linked entries',
        () async {
      // Entry `st2` is linked into `st1`'s scope: nodes are keyed by the
      // SCOPE id, membership rows by the ENTRY id — path equality alone is
      // not the node identity.
      StorageScope.resolver = (id) => id == 'st2' ? 'st1' : id;
      final nodeId = await insertFile('st1', ['D:', 'Videos', '0003.mp4']);
      final tag = await repo.createTag(name: 't');
      await repo.addMember(
        tagId: tag.id,
        storageId: 'st2',
        pathSegments: ['D:/Videos/0003.mp4'],
      );

      expect(await VideoTagMembersDao(db).memberNodeIds(tag.id), [nodeId]);
    });
  });

  group('addedAfter cutoff', () {
    // drift stores DateTime columns as unix SECONDS by default; a raw
    // millisecond binding silently matches nothing (cutoff >> stored value),
    // which made every retention-window index read empty.
    test('memberNodeIds keeps members added at/after the cutoff', () async {
      final nodeId = await insertFile('st1', ['D:', 'Videos', '0004.mp4']);
      final tag = await repo.createTag(name: 't');
      // Added INSIDE the retention window (newer than the cutoff) → kept.
      final thirtyMinAgo = DateTime.now().subtract(const Duration(minutes: 30));
      await repo.addMember(
        tagId: tag.id,
        storageId: 'st1',
        pathSegments: ['D:/Videos/0004.mp4'],
        at: thirtyMinAgo,
      );

      final oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));
      expect(await VideoTagMembersDao(db).memberNodeIds(tag.id,
              addedAfter: oneHourAgo),
          [nodeId],
          reason: 'a member inside the retention window must survive the SQL '
              'cutoff (drift stores the column in unix seconds)');

      final future = DateTime.now().add(const Duration(hours: 1));
      expect(
          await VideoTagMembersDao(db)
              .memberNodeIds(tag.id, addedAfter: future),
          isEmpty);
    });

    test('memberNodeIdsByTag applies the same cutoff', () async {
      final nodeId = await insertFile('st1', ['D:', 'Videos', '0005.mp4']);
      final tag = await repo.createTag(name: 't');
      await repo.addMember(
        tagId: tag.id,
        storageId: 'st1',
        pathSegments: ['D:/Videos/0005.mp4'],
        at: DateTime.now().subtract(const Duration(minutes: 30)),
      );

      final oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));
      expect(await VideoTagMembersDao(db).memberNodeIdsByTag(addedAfter: oneHourAgo),
          [(tagId: tag.id, nodeId: nodeId)]);
    });

    test('countsByTag keeps members added at/after the cutoff', () async {
      final tag = await repo.createTag(name: 't');
      await repo.addMember(
        tagId: tag.id,
        storageId: 'st1',
        pathSegments: ['D:/Videos/0006.mp4'],
        at: DateTime.now().subtract(const Duration(hours: 2)),
      );
      await repo.addMember(
        tagId: tag.id,
        storageId: 'st1',
        pathSegments: ['D:/Videos/0007.mp4'],
      );

      final oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));
      expect(await VideoTagMembersDao(db).countsByTag(addedAfter: oneHourAgo),
          {tag.id: 1},
          reason: 'the retention-aware total must count the fresh member '
              '(drift stores the column in unix seconds)');
    });
  });
}
