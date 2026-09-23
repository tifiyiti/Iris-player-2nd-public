import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/virtual_media/model/domain/vm_item.dart';
import 'package:iris/features/virtual_media/resolver/vm_resume_target.dart';

VirtualSegment _seg(String name, int? durMs, {String storage = 's'}) =>
    VirtualSegment(
      mediaKey: '$storage:$name',
      storageId: storage,
      path: ['d', name],
      name: name,
      parentPath: 'd',
      durationMs: durMs,
    );

VirtualMediaItem _item() => VirtualMediaItem(
      ruleId: 'r',
      scopeKey: 'r|d|#1',
      rootPath: 'd',
      displayIndex: 1,
      displayName: 'd',
      segments: [_seg('a.mp4', 10000), _seg('b.mp4', 20000)],
    );

SegmentProgress _p(int? positionMs, DateTime? at, {bool completed = false}) =>
    (positionMs: positionMs, completed: completed, lastPlayedAt: at);

void main() {
  final t0 = DateTime.utc(2026, 8, 1, 10);
  final t1 = DateTime.utc(2026, 8, 1, 11);
  final t2 = DateTime.utc(2026, 8, 1, 12);

  group('resolveVmResumeByProgress', () {
    test('no progress at all starts at segment 0', () {
      expect(resolveVmResumeByProgress(_item(), const {}), (0, 0));
    });

    test('picks the segment watched most recently', () {
      final result = resolveVmResumeByProgress(_item(), {
        's:a.mp4': _p(9000, t0),
        's:b.mp4': _p(5000, t2),
      });
      expect(result, (1, 5000));
    });

    test('ignores segments whose progress has no timestamp', () {
      final result = resolveVmResumeByProgress(_item(), {
        's:a.mp4': _p(9000, null),
        's:b.mp4': _p(3000, t1),
      });
      expect(result, (1, 3000));
    });

    test('ignores keys absent from the group', () {
      final result = resolveVmResumeByProgress(_item(), {
        's:ghost.mp4': _p(5000, t2),
      });
      expect(result, (0, 0));
    });

    test('position clamps to the segment duration', () {
      final result = resolveVmResumeByProgress(_item(), {
        's:b.mp4': _p(999999, t1),
      });
      // Near-the-end positions clamp back inside the jump-to-end margin.
      expect(result, (1, 20000 - vmResumeEndSafetyMs));
    });

    test('watched-through segment resumes from its head', () {
      final result = resolveVmResumeByProgress(_item(), {
        's:a.mp4': _p(10000, t0),
        's:b.mp4': _p(15000, t2, completed: true),
      });
      expect(result, (1, 0));
    });

    test('unknown duration pins the offset to zero on the right segment', () {
      final item = VirtualMediaItem(
        ruleId: 'r',
        scopeKey: 'r|d|#1',
        rootPath: 'd',
        displayIndex: 1,
        displayName: 'd',
        segments: [_seg('a.mp4', 10000), _seg('u.mp4', null)],
      );
      expect(
        resolveVmResumeByProgress(item, {'s:u.mp4': _p(3000, t1)}),
        (1, 0),
      );
    });

    test('a non-positive saved position resumes that segment from its head',
        () {
      expect(
        resolveVmResumeByProgress(_item(), {'s:b.mp4': _p(0, t1)}),
        (1, 0),
      );
      expect(
        resolveVmResumeByProgress(_item(), {'s:b.mp4': _p(null, t1)}),
        (1, 0),
      );
    });

    test('identity survives a recomposed group (scopeKey changed)', () {
      // Same files, different positional scopeKey — progress still matches.
      final recomposed = VirtualMediaItem(
        ruleId: 'r',
        scopeKey: 'r|d|#7',
        rootPath: 'd',
        displayIndex: 7,
        displayName: 'd',
        segments: [_seg('a.mp4', 10000), _seg('b.mp4', 20000)],
      );
      expect(
        resolveVmResumeByProgress(recomposed, {'s:b.mp4': _p(4000, t1)}),
        (1, 4000),
      );
    });
  });
}
