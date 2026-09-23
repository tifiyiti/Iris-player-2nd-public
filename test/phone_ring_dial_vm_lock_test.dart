import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/phone/one_handed_scrubber/controller/phone_ring_dial_math.dart';
import 'package:iris/features/virtual_media/model/domain/vm_item.dart';

/// `ringDialVmProgressLock` (default ON): the progress ring of a VIRTUAL item
/// clamps its drag inside the file the gesture started in. 0% sticks at the
/// head, 100% at the tail, and a reversed finger moves back immediately
/// (the clamp is on the accumulated target, not the rendered output). The
/// chunk ring and real-file sessions are untouched.
VirtualMediaItem vmItemOf(List<(String, int)> segs) => VirtualMediaItem(
      ruleId: 'r',
      scopeKey: 'r|k|1',
      rootPath: 'k',
      displayIndex: 1,
      displayName: 'k',
      segments: [
        for (final (name, dur) in segs)
          VirtualSegment(
            mediaKey: 'st1:k/$name',
            storageId: 'st1',
            path: ['k', name],
            name: name,
            parentPath: 'k',
            durationMs: dur,
          ),
      ],
    );

void main() {
  // Unequal files: 60s / 659178ms / 30s.
  final item = vmItemOf([
    ('1.mp4', 60000),
    ('2.mp4', 659178),
    ('3.mp4', 30000),
  ]);
  const int file1Head = 60000;
  const int file1TailSeekable = 60000 + 659178 - 1; // 719177

  group('locked progress-ring drag stays inside the starting file', () {
    test('forward sweep saturates at the file tail minus one seekable ms', () {
      final s = PhoneRingDialSession.vm(
        item: item,
        startVirtualMs: file1Head,
        lockToSegment: true,
      );
      s.update(0); // prime
      for (var i = 1; i <= 20; i++) {
        s.update(33.0 * i); // two full revolutions worth of forward motion
      }
      expect(s.targetVirtualMs, closeTo(file1TailSeekable.toDouble(), 1.0),
          reason: 'the lock must stop at the file tail, not cross it');
    });

    test('target never leaves the starting file while sweeping forward', () {
      final s = PhoneRingDialSession.vm(
        item: item,
        startVirtualMs: file1Head,
        lockToSegment: true,
      );
      s.update(0);
      for (var i = 1; i <= 30; i++) {
        s.update(33.0 * i);
        final (int idx, _) = item.locate(s.targetVirtualMs.round());
        expect(idx, 1, reason: 'step $i must stay in file 1');
      }
    });

    test('reversing immediately decreases (no phantom overshoot)', () {
      final s = PhoneRingDialSession.vm(
        item: item,
        startVirtualMs: file1Head,
        lockToSegment: true,
      );
      s.update(0);
      // Saturate the tail.
      for (var i = 1; i <= 20; i++) {
        s.update(33.0 * i);
      }
      final double atTail = s.targetVirtualMs;
      expect(atTail, closeTo(file1TailSeekable.toDouble(), 1.0));

      // One backward step must move AWAY from the tail on the very next
      // update — the clamped target carries no hidden overshoot.
      s.update(33.0 * 20 - 33.0);
      expect(s.targetVirtualMs, lessThan(atTail),
          reason: 'a reversed finger moves back immediately');
    });

    test('backward sweep saturates at the file head', () {
      final s = PhoneRingDialSession.vm(
        item: item,
        startVirtualMs: file1Head,
        lockToSegment: true,
      );
      s.update(0);
      for (var i = 1; i <= 20; i++) {
        s.update(-33.0 * i);
      }
      expect(s.targetVirtualMs, closeTo(file1Head.toDouble(), 1.0),
          reason: 'the lock must stop at the file head, not cross into file 0');
    });
  });

  group('unlocked progress-ring drag keeps walking across files', () {
    test('a full revolution passes the file seam into the next file', () {
      final s = PhoneRingDialSession.vm(
        item: item,
        startVirtualMs: file1Head,
      );
      s.update(0);
      for (var i = 1; i <= 12; i++) {
        s.update(33.0 * i);
      }
      expect(s.targetVirtualMs, greaterThan(file1TailSeekable.toDouble()),
          reason: 'default (no lock) must still cross the seam');
      final (int idx, _) = item.locate(s.targetVirtualMs.round());
      expect(idx, 2);
    });
  });
}
