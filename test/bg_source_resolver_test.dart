import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/model/db/dao/bg_source_rules_dao.dart';
import 'package:iris/features/background_playback/model/db/repositories/bg_source_rule_repository.dart';
import 'package:iris/features/background_playback/model/enum/bg_source_rule_kind.dart';
import 'package:iris/features/background_playback/model/enum/bg_source_sort_field.dart';
import 'package:iris/features/background_playback/model/source/bg_source_rule.dart';
import 'package:iris/features/background_playback/services/background_source_resolver.dart';
import 'package:iris/features/media_library/model/db/dao/media_nodes_dao.dart';
import 'package:iris/features/media_library/model/db/repositories/sub/media_node_repository.dart';
import 'package:iris/features/media_library/model/enum/basic_enum.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/tag_play/model/db/dao/video_tag_members_dao.dart';
import 'package:iris/features/tag_play/model/db/dao/video_tag_pin_presets_dao.dart';
import 'package:iris/features/tag_play/model/db/dao/video_tag_view_states_dao.dart';
import 'package:iris/features/tag_play/model/db/dao/video_tags_dao.dart';
import 'package:iris/features/tag_play/model/db/repositories/tag_play_repository.dart';
import 'package:iris/features/tag_play/model/enum/tag_system_kind.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/utils/dir_match.dart';

import 'helpers/sqlite3_loader.dart';

void main() {
  ensureSqlite3Loaded();
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  // `useStorageStore()` (inside the FileItem builder) reads `DbModule.storageRepo`.
  late AppDatabase moduleDb;
  setUpAll(() async {
    moduleDb = AppDatabase(NativeDatabase.memory());
    await DbModule.init(moduleDb);
  });
  tearDownAll(() => moduleDb.close());

  late AppDatabase db;
  late BgSourceRuleRepository ruleRepo;
  late TagPlayRepository tagRepo;
  late MediaNodeRepository nodeRepo;
  late BackgroundSourceResolver resolver;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    ruleRepo = BgSourceRuleRepository(rulesDao: BgSourceRulesDao(db));
    tagRepo = TagPlayRepository(
      tagsDao: VideoTagsDao(db),
      membersDao: VideoTagMembersDao(db),
      viewStatesDao: VideoTagViewStatesDao(db),
      presetsDao: VideoTagPinPresetsDao(db),
      db: db,
    );
    nodeRepo = MediaNodeRepository(MediaNodesDao(db));
    resolver = BackgroundSourceResolver(
      tagRepo: tagRepo,
      nodeRepo: nodeRepo,
      ruleRepo: ruleRepo,
    );
  });

  tearDown(() => db.close());

  Future<void> insertNode(String storageId, String path) async {
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
      mediaType: MediaType.video,
    ));
  }

  Future<int> reservedBgTagId() async {
    final ensured = await tagRepo.ensureReservedTags();
    return ensured
        .firstWhere(
            (t) => t.systemKind == TagSystemKind.backgroundVoiceCandidate)
        .id;
  }

  test('no enabled rule ⇒ no active source', () async {
    await ruleRepo.saveRule(const BgSourceRule(id: 'off', enabled: false));
    final res = await resolver.resolve();
    expect(res.hasActiveRules, isFalse);
    expect(res.files, isEmpty);
  });

  test('tag rule resolves members newest-tagged first', () async {
    await insertNode('s1', 'Anime/A.mp4');
    await insertNode('s1', 'Anime/B.mp4');
    final tagId = await reservedBgTagId();
    await tagRepo.addMember(
        tagId: tagId,
        storageId: 's1',
        pathSegments: ['Anime', 'A.mp4'],
        at: DateTime(2026, 1, 1));
    await tagRepo.addMember(
        tagId: tagId,
        storageId: 's1',
        pathSegments: ['Anime', 'B.mp4'],
        at: DateTime(2026, 1, 2));
    await ruleRepo.saveRule(BgSourceRule(
      id: 'tag',
      kind: BgSourceRuleKind.tag,
      tagId: tagId,
      sortField: BgSourceSortField.tagAddedAt,
      sortDirection: SortDirection.desc,
    ));

    final res = await resolver.resolve();
    expect(res.hasActiveRules, isTrue);
    expect(res.files.map((f) => f.name).toList(), ['B.mp4', 'A.mp4']);
  });

  test('directory specifiedDir matches only direct children', () async {
    await insertNode('s1', 'Anime/A.mp4');
    await insertNode('s1', 'Anime/Sub/B.mp4');
    await ruleRepo.saveRule(const BgSourceRule(
      id: 'dir',
      kind: BgSourceRuleKind.directory,
      matchMode: DirMatchMode.specifiedDir,
      paths: ['Anime'],
      sortField: BgSourceSortField.name,
      sortDirection: SortDirection.asc,
    ));

    final res = await resolver.resolve();
    expect(res.files.map((f) => f.name).toList(), ['A.mp4']);
  });

  test('directory specifiedDirRecursive includes subdirectories', () async {
    await insertNode('s1', 'Anime/A.mp4');
    await insertNode('s1', 'Anime/Sub/B.mp4');
    await ruleRepo.saveRule(const BgSourceRule(
      id: 'dir',
      kind: BgSourceRuleKind.directory,
      matchMode: DirMatchMode.specifiedDirRecursive,
      paths: ['Anime'],
      sortField: BgSourceSortField.name,
      sortDirection: SortDirection.asc,
    ));

    final res = await resolver.resolve();
    expect(res.files.map((f) => f.name).toList(), ['A.mp4', 'B.mp4']);
  });

  test('directory patternDir matches by parent base name', () async {
    await insertNode('s1', 'ShowS1/A.mp4');
    await insertNode('s1', 'ShowS2/B.mp4');
    await ruleRepo.saveRule(const BgSourceRule(
      id: 'dir',
      kind: BgSourceRuleKind.directory,
      matchMode: DirMatchMode.patternDir,
      patterns: [
        DirPatternEntry(kind: DirPatternKind.suffix, text: 'S1'),
      ],
    ));

    final res = await resolver.resolve();
    expect(res.files.map((f) => f.name).toList(), ['A.mp4']);
  });

  test('directory tag filter intersects with tag members', () async {
    await insertNode('s1', 'Anime/A.mp4');
    await insertNode('s1', 'Anime/B.mp4');
    final tagId = await reservedBgTagId();
    await tagRepo.addMember(
        tagId: tagId,
        storageId: 's1',
        pathSegments: ['Anime', 'B.mp4']);
    await ruleRepo.saveRule(BgSourceRule(
      id: 'dir',
      kind: BgSourceRuleKind.directory,
      matchMode: DirMatchMode.specifiedDirRecursive,
      paths: const ['Anime'],
      tagFilterEnabled: true,
      filterTagId: tagId,
    ));

    final res = await resolver.resolve();
    expect(res.files.map((f) => f.name).toList(), ['B.mp4']);
  });

  test('file rule resolves one explicit file', () async {
    await insertNode('s1', 'Anime/A.mp4');
    await insertNode('s1', 'Anime/B.mp4');
    await ruleRepo.saveRule(const BgSourceRule(
      id: 'file',
      kind: BgSourceRuleKind.file,
      fileStorageId: 's1',
      filePath: 'Anime/B.mp4',
    ));

    final res = await resolver.resolve();
    expect(res.files.map((f) => f.name).toList(), ['B.mp4']);
  });

  test('cross-rule dedupe follows the global switch', () async {
    await insertNode('s1', 'Anime/A.mp4');
    await ruleRepo.saveRule(const BgSourceRule(
      id: 'r1',
      kind: BgSourceRuleKind.directory,
      matchMode: DirMatchMode.specifiedDir,
      paths: ['Anime'],
    ));
    await ruleRepo.saveRule(const BgSourceRule(
      id: 'r2',
      kind: BgSourceRuleKind.directory,
      matchMode: DirMatchMode.specifiedDir,
      paths: ['Anime'],
    ));

    final off = await resolver.resolve(dedupe: false);
    expect(off.files.map((f) => f.name).toList(), ['A.mp4', 'A.mp4']);

    final on = await resolver.resolve(dedupe: true);
    expect(on.files.map((f) => f.name).toList(), ['A.mp4']);
  });
}
