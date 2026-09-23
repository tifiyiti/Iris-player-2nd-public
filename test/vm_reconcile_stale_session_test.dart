import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/virtual_media/model/domain/vm_item.dart';
import 'package:iris/features/virtual_media/playback/vm_playback_controller.dart';
import 'package:iris/features/virtual_media/store/vm_playback_store.dart';

VirtualMediaItem _item() => VirtualMediaItem(
      ruleId: 'r',
      scopeKey: 'r|d|#1',
      rootPath: 'd',
      displayIndex: 1,
      displayName: 'd',
      segments: [
        VirtualSegment(
          mediaKey: 's:d/a.mp4',
          storageId: 's',
          path: const ['d', 'a.mp4'],
          name: 'a.mp4',
          parentPath: 'd',
          durationMs: 100000,
        ),
        VirtualSegment(
          mediaKey: 's:d/b.mp4',
          storageId: 's',
          path: const ['d', 'b.mp4'],
          name: 'b.mp4',
          parentPath: 'd',
          durationMs: 100000,
        ),
      ],
    );

void main() {
  final ctrl = VirtualMediaController.instance;

  tearDown(() => useVmPlaybackStore().replace(const VmPlaybackState()));

  test('reconcileStaleSession clears an item with no active session', () {
    useVmPlaybackStore().replace(VmPlaybackState(item: _item()));
    expect(useVmPlaybackStore().state.item, isNotNull);
    // No feed ever ran land (_expectedSegmentKey null) and the queue does not
    // match: this is exactly the stale state left by a direct normal-file open.
    expect(ctrl.isActive, isFalse);

    ctrl.reconcileStaleSession();

    expect(useVmPlaybackStore().state.item, isNull);
  });

  test('reconcileStaleSession keeps a transitioning session', () {
    useVmPlaybackStore().replace(VmPlaybackState(
      item: _item(),
      transitioning: true,
      pendingSeekMs: 0,
    ));

    ctrl.reconcileStaleSession();

    expect(useVmPlaybackStore().state.item, isNotNull,
        reason: 'a switch in flight must not be torn down');
  });
}
