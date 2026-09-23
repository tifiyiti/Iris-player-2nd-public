import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/services/bg_vm_visibility.dart';
import 'package:iris/features/virtual_media/model/domain/vm_item.dart';
import 'package:iris/features/virtual_media/view/vm_scrubber_marks.dart';

VirtualMediaItem _item() => VirtualMediaItem(
      ruleId: 'r',
      scopeKey: 'r|root|#1',
      rootPath: '',
      displayIndex: 1,
      displayName: 'g',
      segments: const [
        VirtualSegment(
          mediaKey: 's:a',
          storageId: 's',
          path: ['a.mp4'],
          name: 'a.mp4',
          parentPath: '',
          durationMs: 60000,
        ),
        VirtualSegment(
          mediaKey: 's:b',
          storageId: 's',
          path: ['b.mp4'],
          name: 'b.mp4',
          parentPath: '',
          durationMs: 90000,
        ),
      ],
    );

void main() {
  // 副音 (bg) plays REAL single files only. While the controls target bg the
  // foreground's virtual session must not decorate the bg scrubber.
  group('vmItemForControlTarget', () {
    test('keeps the VM item for the foreground target', () {
      final item = _item();
      expect(vmItemForControlTarget(item, bgIsControl: false), same(item));
    });

    test('suppresses the VM item for the background target', () {
      expect(vmItemForControlTarget(_item(), bgIsControl: true), isNull);
    });

    test('null stays null either way', () {
      expect(vmItemForControlTarget(null, bgIsControl: false), isNull);
      expect(vmItemForControlTarget(null, bgIsControl: true), isNull);
    });
  });

  group('showVmScrubberMarks', () {
    test('false without a VM item', () {
      expect(
        showVmScrubberMarks(vmItemPresent: false, bgIsControl: false),
        isFalse,
      );
    });

    test('true for the foreground target with a VM item', () {
      expect(
        showVmScrubberMarks(vmItemPresent: true, bgIsControl: false),
        isTrue,
      );
    });

    test('false for the background target even with a VM item', () {
      expect(
        showVmScrubberMarks(vmItemPresent: true, bgIsControl: true),
        isFalse,
      );
    });
  });

  test('bg target empties the scrubber marks (single-file track)', () {
    final item = _item();
    expect(
      computeVmScrubberMarks(
        vmItemForControlTarget(item, bgIsControl: false),
      ).isEmpty,
      isFalse,
    );
    expect(
      computeVmScrubberMarks(
        vmItemForControlTarget(item, bgIsControl: true),
      ).isEmpty,
      isTrue,
    );
  });
}
