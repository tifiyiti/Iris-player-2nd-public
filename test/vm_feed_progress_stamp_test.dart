import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/scenario_playback/playback/playback_progress.dart';
import 'package:iris/features/virtual_media/model/domain/vm_item.dart';
import 'package:iris/features/virtual_media/resolver/vm_resume_target.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/utils/path_conv.dart';

import 'helpers/sqlite3_loader.dart';

/// The VM session resume picks the segment with the newest `lastPlayedAt`
/// (`resolveVmResumeByProgress`). The feed pre-write must therefore STAMP the
/// fed segment as the most-recently-watched one — otherwise a re-resolution
/// (rule edit, tag switch, cold-start resume) selects an older / first segment,
/// which is the "回退到第一个视频" symptom.
///
/// The controller feed itself carries global DB/store singletons and is
/// verified on device (see the [vm-seek]/[vm-jump] diagnostic logs); these
/// tests pin the two things that make the stamp work: the resume selection is
/// lastPlayedAt-driven, and the progress write round-trips `lastPlayedAt`.
void main() {
  setUpAll(() async {
    ensureSqlite3Loaded();
    DbModule.init(AppDatabase(NativeDatabase.memory()));
  });

  VirtualMediaItem item() => VirtualMediaItem(
        ruleId: 'r',
        scopeKey: 'sc',
        rootPath: 'dir',
        displayIndex: 0,
        displayName: 'group',
        segments: const [
          VirtualSegment(
            mediaKey: 's:seg0.mp4',
            storageId: 's',
            path: ['seg0.mp4'],
            name: 'seg0.mp4',
            parentPath: '',
            durationMs: 60000,
          ),
          VirtualSegment(
            mediaKey: 's:seg1.mp4',
            storageId: 's',
            path: ['seg1.mp4'],
            name: 'seg1.mp4',
            parentPath: '',
            durationMs: 60000,
          ),
          VirtualSegment(
            mediaKey: 's:seg2.mp4',
            storageId: 's',
            path: ['seg2.mp4'],
            name: 'seg2.mp4',
            parentPath: '',
            durationMs: 60000,
          ),
        ],
      );

  Future<void> seedNode(String name) async {
    await DbModule.mediaNodesDao.insertNode(MediaNode.file(
      id: 'f:s:$name',
      storageId: 's',
      path: [name],
      name: name,
      mediaType: MediaType.video,
    ));
  }

  group('resolveVmResumeByProgress selection', () {
    test('picks the segment with the newest lastPlayedAt, not segment 0', () {
      final now = DateTime.now();
      final (idx, local) = resolveVmResumeByProgress(item(), {
        's:seg0.mp4': (
          positionMs: 5000,
          completed: false,
          lastPlayedAt: now.subtract(const Duration(hours: 2)),
        ),
        's:seg1.mp4': (
          positionMs: 30000,
          completed: false,
          lastPlayedAt: now.subtract(const Duration(hours: 1)),
        ),
        's:seg2.mp4': (
          positionMs: 0,
          completed: false,
          lastPlayedAt: now,
        ),
      });
      expect(idx, 2);
      expect(local, 0);
    });

    test('no progress anywhere falls back to segment 0', () {
      final (idx, local) = resolveVmResumeByProgress(item(), const {});
      expect(idx, 0);
      expect(local, 0);
    });
  });

  group('feed pre-write stamp round-trip', () {
    test('a targeted pre-write records lastPlayedAt for the fed segment',
        () async {
      await seedNode('seg2.mp4');
      final before = DateTime.now().subtract(const Duration(days: 1));
      await DbModule.mediaNodeRepo.updatePlaybackProgress(
        storageId: 's',
        path: 'seg2.mp4',
        positionMs: 0,
        lastPlayedAt: before,
      );
      // The controller's `_doFeedCurrent` pre-write writes the target with a
      // fresh stamp; the row must then report it as the newest played file.
      await DbModule.mediaNodeRepo.updatePlaybackProgress(
        storageId: 's',
        path: 'seg2.mp4',
        positionMs: 0,
        completed: false,
        lastPlayedAt: DateTime.now(),
        historyRestoreBudgetMs: 0,
        intent: ProgressWriteIntent.targeted,
        writeTag: 'vm-prewrite',
      );
      final progress =
          await DbModule.mediaNodeRepo.progressForMediaKeys({'s:seg2.mp4'});
      final entry = progress[canonicalKey('s', 'seg2.mp4')];
      expect(entry, isNotNull);
      expect(entry!.positionMs, 0);
      expect(entry.completed, isFalse);
      expect(entry.lastPlayedAt!.isAfter(before), isTrue);
    });
  });
}
