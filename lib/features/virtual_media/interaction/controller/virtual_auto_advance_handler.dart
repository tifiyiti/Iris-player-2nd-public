import 'package:iris/features/media_library/model/db/repositories/sub/progress_write_guard.dart';
import 'package:iris/features/virtual_media/playback/vm_playback_controller.dart';
import 'package:iris/models/db/db_module.dart';

/// Natural completion → next segment from 0, current segment marked 0.
///
/// Later segment wins at boundaries (prefix inclusive left, already
/// honoured by [VirtualMediaItem.locate]).
class VirtualAutoAdvanceHandler {
  const VirtualAutoAdvanceHandler();

  Future<bool> handleCompleted() async {
    final ctrl = VirtualMediaController.instance;
    if (!ctrl.isActive) return false;
    // Mark current segment position 0 before advance (spec §3).
    try {
      final seg = ctrl.currentSegment;
      await DbModule.mediaNodeRepo.updatePlaybackProgress(
        storageId: seg.storageId,
        path: seg.path.join('/'),
        positionMs: 0,
        completed: true,
        intent: ProgressWriteIntent.explicitClear,
        writeTag: 'vm-advance',
      );
    } catch (_) {}
    return ctrl.maybeHandleCompleted();
  }
}
