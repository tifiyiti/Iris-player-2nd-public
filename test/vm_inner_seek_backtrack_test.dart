import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/virtual_media/model/domain/vm_item.dart';
import 'package:iris/features/virtual_media/playback/vm_playback_controller.dart';

VirtualSegment _seg(String name, int durMs) => VirtualSegment(
      mediaKey: 's:$name',
      storageId: 's',
      path: ['d', name],
      name: name,
      parentPath: 'd',
      durationMs: durMs,
    );

VirtualMediaItem _item({List<VirtualSegment>? segments, String? scopeKey}) =>
    VirtualMediaItem(
      ruleId: 'r',
      scopeKey: scopeKey ?? 'r|d|#1',
      rootPath: 'd',
      displayIndex: 1,
      displayName: 'd',
      segments: segments ?? [_seg('a.mp4', 10000), _seg('b.mp4', 20000)],
    );

void main() {
  group('vmRevalidateDeferredJump (feed-serialized jump target validity)', () {
    final item = _item();

    test('same scope, in-range, not-yet-landed target is still valid', () {
      expect(
        vmRevalidateDeferredJump(
          targetScopeKey: item.scopeKey,
          index: 1,
          currentItem: item,
          currentSegmentIndex: 0,
        ),
        isTrue,
      );
    });

    test('session moved to another scope (cross-body feed) drops the jump', () {
      final other = _item(scopeKey: 'r|d|#2');
      expect(
        vmRevalidateDeferredJump(
          targetScopeKey: item.scopeKey,
          index: 1,
          currentItem: other,
          currentSegmentIndex: 0,
        ),
        isFalse,
      );
    });

    test('feed already landed on the target segment collapses to a no-op', () {
      expect(
        vmRevalidateDeferredJump(
          targetScopeKey: item.scopeKey,
          index: 1,
          currentItem: item,
          currentSegmentIndex: 1,
        ),
        isFalse,
      );
    });

    test('target out of range on the post-feed item drops the jump', () {
      final shorter = _item(segments: [_seg('a.mp4', 10000)]);
      expect(
        vmRevalidateDeferredJump(
          targetScopeKey: shorter.scopeKey,
          index: 1,
          currentItem: shorter,
          currentSegmentIndex: 0,
        ),
        isFalse,
      );
    });

    test('session ended (no item) drops the jump', () {
      expect(
        vmRevalidateDeferredJump(
          targetScopeKey: item.scopeKey,
          index: 1,
          currentItem: null,
          currentSegmentIndex: 0,
        ),
        isFalse,
      );
    });
  });
}
