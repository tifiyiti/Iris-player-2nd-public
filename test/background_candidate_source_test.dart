import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/db/dao/media_nodes_dao.dart';
import 'package:iris/features/media_library/model/db/repositories/sub/media_node_repository.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/tag_play/model/db/dao/video_tag_members_dao.dart';
import 'package:iris/features/tag_play/model/db/dao/video_tag_pin_presets_dao.dart';
import 'package:iris/features/tag_play/model/db/dao/video_tag_view_states_dao.dart';
import 'package:iris/features/tag_play/model/db/dao/video_tags_dao.dart';
import 'package:iris/features/tag_play/model/db/repositories/tag_play_repository.dart';
import 'package:iris/features/tag_play/model/enum/tag_system_kind.dart';
import 'package:iris/features/tag_play/playback/tag_voice_candidate_source.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/file.dart';

import 'helpers/sqlite3_loader.dart';

void main() {
  ensureSqlite3Loaded();
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  // The storage store reads DbModule.storageRepo (statics) — initialize once
  // on a module DB; per-test DBs drive tags/nodes through injected repos.
  late AppDatabase moduleDb;
  setUpAll(() async {
    moduleDb = AppDatabase(NativeDatabase.memory());
    await DbModule.init(moduleDb);
  });
  tearDownAll(() => moduleDb.close());

  late AppDatabase db;
  late TagPlayRepository tagRepo;
  late MediaNodeRepository nodeRepo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tagRepo = TagPlayRepository(
      tagsDao: VideoTagsDao(db),
      membersDao: VideoTagMembersDao(db),
      viewStatesDao: VideoTagViewStatesDao(db),
      presetsDao: VideoTagPinPresetsDao(db),
      db: db,
    );
    nodeRepo = MediaNodeRepository(MediaNodesDao(db));
  });

  tearDown(() => db.close());

  Future<void> insertNode(String storageId, String path,
      {MediaType mediaType = MediaType.video}) async {
    final segments = path.split('/');
    await MediaNodesDao(db).insertNode(MediaNode.file(
      id: '$storageId:$path',
      storageId: storageId,
      path: segments,
      parentPath: segments.length == 1
          ? null
          : segments.sublist(0, segments.length - 1).join('/'),
      pathDepth: segments.length,
      name: segments.last,
      mediaType: mediaType,
    ));
  }

  Future<int> reservedBgTagId() async {
    final ensured = await tagRepo.ensureReservedTags();
    return ensured
        .firstWhere(
            (t) => t.systemKind == TagSystemKind.backgroundVoiceCandidate)
        .id;
  }

  group('TagVoiceCandidateSource (副音备选 → 真单文件)', () {
    test('no reserved tag ⇒ empty candidates', () async {
      final source = TagVoiceCandidateSource(
        tagRepo: tagRepo,
        nodeRepo: nodeRepo,
      );
      expect(await source.resolveCandidates(), isEmpty);
    });

    test('resolves real files, newest-tagged first, and skips vanished ones',
        () async {
      await insertNode('s1', 'Anime/A.mp4');
      await insertNode('s1', 'Anime/B.mp4');
      await insertNode('s1', 'Anime/C.mp4');
      final tagId = await reservedBgTagId();

      await tagRepo.addMember(
          tagId: tagId,
          storageId: 's1',
          pathSegments: ['Anime', 'A.mp4'],
          at: DateTime(2026, 1, 1, 0, 0, 0));
      await tagRepo.addMember(
          tagId: tagId,
          storageId: 's1',
          pathSegments: ['Anime', 'B.mp4'],
          at: DateTime(2026, 1, 1, 0, 1, 0));
      // A member whose file never made it into media_nodes (deleted/moved).
      await tagRepo.addMember(
          tagId: tagId,
          storageId: 's1',
          pathSegments: ['Anime', 'Ghost.mp4'],
          at: DateTime(2026, 1, 1, 0, 2, 0));

      final source = TagVoiceCandidateSource(
        tagRepo: tagRepo,
        nodeRepo: nodeRepo,
      );
      final files = await source.resolveCandidates();

      // B tagged last → first; Ghost absent → silently skipped.
      expect(files.map((f) => f.name).toList(), ['B.mp4', 'A.mp4']);
      expect(files.first.uri, endsWith('Anime/B.mp4'));
      // Real single files only.
      expect(
        files.every((f) =>
            f.type == ContentType.video || f.type == ContentType.audio),
        isTrue,
      );
    });

    test('cap limits the returned list', () async {
      for (final i in List.generate(5, (i) => i)) {
        await insertNode('s1', 'v/$i.mp4');
      }
      final tagId = await reservedBgTagId();
      for (final i in List.generate(5, (i) => i)) {
        await tagRepo.addMember(
            tagId: tagId, storageId: 's1', pathSegments: ['v', '$i.mp4']);
      }
      final source = TagVoiceCandidateSource(
        tagRepo: tagRepo,
        nodeRepo: nodeRepo,
      );
      expect((await source.resolveCandidates(cap: 2)).length, 2);
    });
  });
}
