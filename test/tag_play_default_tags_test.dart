import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/tag_play/model/db/dao/video_tag_members_dao.dart';
import 'package:iris/features/tag_play/model/db/dao/video_tag_pin_presets_dao.dart';
import 'package:iris/features/tag_play/model/db/dao/video_tag_view_states_dao.dart';
import 'package:iris/features/tag_play/model/db/dao/video_tags_dao.dart';
import 'package:iris/features/tag_play/model/db/repositories/tag_play_repository.dart';
import 'package:iris/features/tag_play/model/enum/tag_system_kind.dart';
import 'package:iris/features/tag_play/store/tag_play_bootstrap.dart';
import 'package:iris/models/db/app_database.dart';

import 'helpers/sqlite3_loader.dart';

void main() {
  ensureSqlite3Loaded();

  late AppDatabase db;
  late TagPlayRepository repo;

  setUp(() async {
    TagPlayBootstrap.resetForTests();
    db = AppDatabase(NativeDatabase.memory());
    repo = TagPlayRepository(
      tagsDao: VideoTagsDao(db),
      membersDao: VideoTagMembersDao(db),
      viewStatesDao: VideoTagViewStatesDao(db),
      presetsDao: VideoTagPinPresetsDao(db),
      db: db,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('system-reserved tags', () {
    test('ensure() creates exactly the three reserved tags with their roles',
        () async {
      await TagPlayBootstrap.ensure(repo);

      final tags = await repo.tags();
      expect(tags, hasLength(3));

      final byKind = {
        for (final t in tags)
          if (t.systemKind != null) t.systemKind!: t,
      };
      expect(byKind, hasLength(3));
      expect(TagSystemKind.values.every(byKind.containsKey), isTrue);

      // Canonical names stored as content (existing seed convention).
      expect(byKind[TagSystemKind.tempMarker]!.name, '临时标记');
      expect(byKind[TagSystemKind.favorite]!.name, '永久收藏');
      expect(
          byKind[TagSystemKind.backgroundVoiceCandidate]!.name, '副音备选');

      // 临时标记 keeps its historical jump-back/expiry policies.
      expect(byKind[TagSystemKind.tempMarker]!.retention,
          const Duration(hours: 6));
      expect(byKind[TagSystemKind.tempMarker]!.resumeWindow,
          const Duration(minutes: 30));
      // 永久收藏 / 副音备选: permanent everything.
      expect(byKind[TagSystemKind.favorite]!.retention, isNull);
      expect(byKind[TagSystemKind.favorite]!.resumeWindow, isNull);
      expect(
          byKind[TagSystemKind.backgroundVoiceCandidate]!.retention, isNull);
      expect(
          byKind[TagSystemKind.backgroundVoiceCandidate]!.resumeWindow, isNull);
    });

    test('is idempotent across repeated calls', () async {
      await TagPlayBootstrap.ensure(repo);
      await TagPlayBootstrap.ensure(repo);
      await TagPlayBootstrap.ensure(repo);

      expect(await repo.tags(), hasLength(3));
    });

    test('reserved tags survive delete attempts', () async {
      await TagPlayBootstrap.ensure(repo);
      for (final t in await repo.tags()) {
        expect(await repo.deleteTagCascade(t.id), isFalse,
            reason: 'reserved tag ${t.name} must refuse deletion');
      }

      await TagPlayBootstrap.ensure(repo);

      final tags = await repo.tags();
      expect(tags, hasLength(3));
      expect(tags.every((t) => t.systemKind != null), isTrue);
    });

    test('reserved tags cannot be renamed, re-roled or un-reserved', () async {
      await TagPlayBootstrap.ensure(repo);
      final favorite =
          (await repo.tags()).firstWhere((t) => t.name == '永久收藏');

      // Rename refused.
      await repo.updateTag(favorite.copyWith(name: '改了个名'));
      final afterRename = await repo.tagById(favorite.id);
      expect(afterRename!.name, '永久收藏');

      // Role change refused.
      await repo.updateTag(
          favorite.copyWith(systemKind: TagSystemKind.tempMarker));
      final afterRole = await repo.tagById(favorite.id);
      expect(afterRole!.systemKind, TagSystemKind.favorite);

      // Un-reserve refused.
      await repo.updateTag(favorite.copyWith(systemKind: null));
      final afterUnreserve = await repo.tagById(favorite.id);
      expect(afterUnreserve!.systemKind, TagSystemKind.favorite);

      // Description (non-identity field) stays editable.
      await repo.updateTag(favorite.copyWith(description: '改了描述'));
      final afterDesc = await repo.tagById(favorite.id);
      expect(afterDesc!.description, '改了描述');
    });

    test('plain user tags keep delete/rename behavior', () async {
      await TagPlayBootstrap.ensure(repo);
      final user = await repo.createTag(name: '待看', description: '随手');

      await repo.updateTag(user.copyWith(name: '改名', description: ''));
      expect((await repo.tagById(user.id))!.name, '改名');

      expect(await repo.deleteTagCascade(user.id), isTrue);
      expect(await repo.tagById(user.id), isNull);

      // Reserved trio unaffected by the user CRUD above.
      expect(await repo.tags(), hasLength(3));
    });

    test('legacy v1-era user tags stay untouched while reserved rows appear',
        () async {
      // Simulate a pre-v25 database holding the old deletable seeds under
      // their v1 names.
      final like = await repo.createTag(name: '喜欢', description: 'v1 收藏');
      final tempLike =
          await repo.createTag(name: '临时喜欢', description: 'v1 临时');

      await TagPlayBootstrap.ensure(repo);

      final tags = await repo.tags();
      expect(tags, hasLength(5)); // 2 legacy user tags + 3 reserved
      final byId = {for (final t in tags) t.id: t};
      // v1 rows were NOT renamed in place — they stay plain user tags.
      expect(byId[like.id]!.name, '喜欢');
      expect(byId[like.id]!.systemKind, isNull);
      expect(byId[tempLike.id]!.name, '临时喜欢');
      expect(byId[tempLike.id]!.systemKind, isNull);
      // Reserved trio exists alongside.
      final byKind = {
        for (final t in tags)
          if (t.systemKind != null) t.systemKind!: t,
      };
      expect(TagSystemKind.values.every(byKind.containsKey), isTrue);
    });

    test('adopts a same-name user tag into its reserved role', () async {
      // A user tag that happened to carry a canonical name is claimed.
      final user = await repo.createTag(
        name: '副音备选',
        description: '用户自建',
        retention: const Duration(days: 3),
      );

      await TagPlayBootstrap.ensure(repo);

      final adopted = await repo.tagById(user.id);
      expect(adopted!.systemKind, TagSystemKind.backgroundVoiceCandidate);
      // Adoption normalizes description + policies to the canonical role row.
      expect(adopted.name, '副音备选');
      expect(adopted.description, '副音播放候选源');
      expect(adopted.retention, isNull);
      expect(adopted.resumeWindow, isNull);
      // No extra duplicate row was created.
      expect(await repo.tags(), hasLength(3));
    });
  });
}
