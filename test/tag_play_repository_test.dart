import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/tag_play/model/db/dao/video_tag_members_dao.dart';
import 'package:iris/features/tag_play/model/db/dao/video_tag_pin_presets_dao.dart';
import 'package:iris/features/tag_play/model/db/dao/video_tag_view_states_dao.dart';
import 'package:iris/features/tag_play/model/db/dao/video_tags_dao.dart';
import 'package:iris/features/tag_play/model/db/repositories/tag_play_repository.dart';
import 'package:iris/features/tag_play/model/domain/tag_play_pin_preset.dart';
import 'package:iris/features/tag_play/model/domain/tag_play_view_state.dart';
import 'package:iris/models/db/app_database.dart';

import 'helpers/sqlite3_loader.dart';

void main() {
  ensureSqlite3Loaded();

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  TagPlayRepository buildRepo() => TagPlayRepository(
        tagsDao: VideoTagsDao(db),
        membersDao: VideoTagMembersDao(db),
        viewStatesDao: VideoTagViewStatesDao(db),
        presetsDao: VideoTagPinPresetsDao(db),
        db: db,
      );

  group('tag_play repository', () {
    test('create/read/update/delete tag roundtrip', () async {
      final r = buildRepo();

      final created = await r.createTag(
        name: '待看',
        description: '临时收集',
        retention: const Duration(hours: 6),
      );
      expect(created.id, greaterThan(0));
      expect(created.name, '待看');
      expect(created.retention, const Duration(hours: 6));

      final fetched = await r.tagById(created.id);
      expect(fetched, isNotNull);
      expect(fetched!.description, '临时收集');

      final updated =
          fetched.copyWith(description: '改过的描述', retention: null);
      await r.updateTag(updated);
      final refetched = await r.tagById(created.id);
      expect(refetched!.description, '改过的描述');
      expect(refetched.retention, isNull);

      await r.deleteTagCascade(created.id);
      expect(await r.tagById(created.id), isNull);
    });

    test('membership add/remove + canonical path normalization', () async {
      final r = buildRepo();
      final tag = await r.createTag(name: '喜欢');

      await r.addMember(
        tagId: tag.id,
        storageId: 's1',
        pathSegments: ['Anime', 'A', '01.mp4'],
        at: DateTime.utc(2026, 8, 1),
      );
      // Same file with different slash conventions → same membership.
      await r.addMember(
        tagId: tag.id,
        storageId: 's1',
        pathSegments: ['/Anime/A/', '01.mp4'],
        at: DateTime.utc(2026, 8, 2),
      );

      final members = await r.membersOf(tag.id);
      expect(members, hasLength(1));
      expect(members.first.mediaKey, 's1:Anime/A/01.mp4');
      // Re-add refreshes addedAt.
      expect(members.first.addedAt.isAtSameMomentAs(DateTime.utc(2026, 8, 2)),
          isTrue);

      await r.removeMember(
          tagId: tag.id,
          storageId: 's1',
          pathSegments: ['Anime', 'A', '01.mp4']);
      expect(await r.membersOf(tag.id), isEmpty);
    });

    test('membershipsOf returns all tags containing a media', () async {
      final r = buildRepo();
      final t1 = await r.createTag(name: 'a');
      final t2 = await r.createTag(name: 'b');

      await r.addMember(
          tagId: t1.id,
          storageId: 's1',
          pathSegments: ['v', 'x.mp4'],
          at: DateTime.utc(2026, 8, 1));
      await r.addMember(
          tagId: t2.id,
          storageId: 's1',
          pathSegments: ['v', 'x.mp4'],
          at: DateTime.utc(2026, 8, 1));

      final ids = await r.membershipsOf(storageId: 's1', pathSegments: ['v', 'x.mp4']);
      expect(ids, {t1.id, t2.id});
    });

    test('lazy expiry hides expired members but keeps rows until purge',
        () async {
      final r = buildRepo();
      final now = DateTime.utc(2026, 8, 10, 12);
      final tag = await r.createTag(
        name: 't',
        retention: const Duration(hours: 6));

      await r.addMember(
          tagId: tag.id,
          storageId: 's1',
          pathSegments: ['old.mp4'],
          at: now.subtract(const Duration(hours: 7)));
      await r.addMember(
          tagId: tag.id,
          storageId: 's1',
          pathSegments: ['fresh.mp4'],
          at: now.subtract(const Duration(hours: 1)));

      final active = await r.activeMembersOf(tag.id, now: now);
      expect(active.map((m) => m.path.split('/').last), ['fresh.mp4']);

      // Raw read still sees both (lazy semantics).
      expect(await r.membersOf(tag.id), hasLength(2));

      // Permanent tag keeps everything.
      final perm = await r.createTag(name: 'perm');
      await r.addMember(
          tagId: perm.id,
          storageId: 's1',
          pathSegments: ['ancient.mp4'],
          at: now.subtract(const Duration(days: 400)));
      expect(await r.activeMembersOf(perm.id, now: now), hasLength(1));
    });

    test('purgeExpired deletes only expired rows and is idempotent', () async {
      final r = buildRepo();
      final now = DateTime.utc(2026, 8, 10, 12);
      final expiring = await r.createTag(
        name: 't',
        retention: const Duration(minutes: 5));
      final permanent = await r.createTag(name: 'perm');

      await r.addMember(
          tagId: expiring.id,
          storageId: 's',
          pathSegments: ['gone.mp4'],
          at: now.subtract(const Duration(minutes: 6)));
      await r.addMember(
          tagId: expiring.id,
          storageId: 's',
          pathSegments: ['stay.mp4'],
          at: now.subtract(const Duration(minutes: 4)));
      await r.addMember(
          tagId: permanent.id,
          storageId: 's',
          pathSegments: ['forever.mp4'],
          at: now.subtract(const Duration(days: 365)));

      final removed = await r.purgeExpired(now: now);
      expect(removed, 1);

      expect((await r.activeMembersOf(expiring.id, now: now)).single.path
          .split('/')
          .last, 'stay.mp4');
      expect(await r.activeMembersOf(permanent.id, now: now), hasLength(1));

      expect(await r.purgeExpired(now: now), 0);
    });

    test('deleteTagCascade removes members and view state together', () async {
      final r = buildRepo();
      final tag = await r.createTag(name: 'temp');
      await r.addMember(
          tagId: tag.id,
          storageId: 's',
          pathSegments: ['a.mp4'],
          at: DateTime.utc(2026, 8, 1));
      await r.saveState(TagPlayViewState(tagId: tag.id, lastMediaKey: 's:a.mp4'));

      await r.deleteTagCascade(tag.id);

      expect(await r.membersOf(tag.id), isEmpty);
      expect(await r.stateOf(tag.id), isNull);
    });

    test('latestActiveMember respects retention window', () async {
      final r = buildRepo();
      final now = DateTime.utc(2026, 8, 10, 12);
      final tag = await r.createTag(
        name: 't',
        retention: const Duration(hours: 2));

      expect(await r.latestActiveMember(tag.id, now: now), isNull);

      await r.addMember(
          tagId: tag.id,
          storageId: 's',
          pathSegments: ['stale.mp4'],
          at: now.subtract(const Duration(hours: 3)));
      expect(await r.latestActiveMember(tag.id, now: now), isNull);

      await r.addMember(
          tagId: tag.id,
          storageId: 's',
          pathSegments: ['new.mp4'],
          at: now.subtract(const Duration(minutes: 30)));
      final latest = await r.latestActiveMember(tag.id, now: now);
      expect(latest!.path.split('/').last, 'new.mp4');
    });

    test('pin preset save/load/delete roundtrip', () async {
      final r = buildRepo();
      final id = await r.savePreset(const TagPlayPinPreset(
        id: 0,
        name: '扫盘套装',
        pinnedTagIds: [3, 1, 2],
      ));

      final loaded = await r.presets();
      expect(loaded.single.id, id);
      expect(loaded.single.pinnedTagIds, [3, 1, 2]);

      await r.savePreset(TagPlayPinPreset(
        id: id,
        name: '改名了',
        pinnedTagIds: [9],
      ));
      final reloaded = await r.presets();
      expect(reloaded.single.name, '改名了');
      expect(reloaded.single.pinnedTagIds, [9]);

      await r.deletePreset(id);
      expect(await r.presets(), isEmpty);
    });

    test('tagsOfMediaKeys bulk lookup maps canonical keys to tag names',
        () async {
      final r = buildRepo();
      final a = await r.createTag(name: '甲');
      final b = await r.createTag(name: '乙');

      await r.addMember(tagId: a.id, storageId: 's1', pathSegments: ['v/x.mp4']);
      await r.addMember(tagId: b.id, storageId: 's1', pathSegments: ['v/x.mp4']);
      await r.addMember(tagId: a.id, storageId: 's2', pathSegments: ['w.mp4']);

      // Canonical keys mirror TagPlayMember.mediaKey ($storageId:$canonicalPath).
      const keyX = 's1:v/x.mp4';
      const keyW = 's2:w.mp4';
      const keyMissing = 's9:nope.mp4';

      final map = await r.tagsOfMediaKeys({keyX, keyW, keyMissing});

      expect(map[keyX]!.map((t) => t.name).toSet(), {'甲', '乙'});
      expect(map[keyW]!.map((t) => t.name).toSet(), {'甲'});
      // Prefilled empty list → distinguishable from "not yet loaded".
      expect(map[keyMissing], isEmpty);
      expect(map.containsKey(keyMissing), isTrue);
    });
  });
}
