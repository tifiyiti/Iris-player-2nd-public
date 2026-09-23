import 'package:iris/features/background_playback/model/db/repositories/background_mapping_repository.dart';
import 'package:iris/features/background_playback/model/domain/background_mapping.dart';
import 'package:iris/features/background_playback/resolver/mapping_binding.dart';
import 'package:iris/models/db/db_module.dart';

/// Returns [timeline] with [target]'s background file swapped while its
/// foreground placement (A/B) and alignment (P) stay unchanged.
///
/// This is the manager's position/binding decoupling: the same span/position can
/// be pointed at a different bg. [target] is matched by its id (or its fg range
/// when the id is 0), so a staged (in-memory) segment is replaceable.
BackgroundMappingTimeline replaceSegmentBg(
  BackgroundMappingTimeline timeline,
  MappingSegment target, {
  required String bgStorageId,
  required String bgPath,
  int? bgTotalMs,
}) {
  final segments = [
    for (final s in timeline.segments)
      _sameSegment(s, target)
          ? MappingBinding.replaceBgKeepingSpan(
              s,
              bgStorageId: bgStorageId,
              bgPath: bgPath,
              bgTotalMs: bgTotalMs,
            )
          : s,
  ];
  return timeline.copyWith(segments: segments);
}

bool _sameSegment(MappingSegment a, MappingSegment b) {
  if (a.id != 0 && b.id != 0) return a.id == b.id;
  return a.fgStartMs == b.fgStartMs && a.fgEndMs == b.fgEndMs;
}


/// Outcome of committing a staged mapping timeline.
enum MappingApplyStatus { ok, conflict, invalid, writeFailed }

class MappingApplyOutcome {
  const MappingApplyOutcome(this.status, [this.message]);

  final MappingApplyStatus status;
  final String? message;

  bool get ok => status == MappingApplyStatus.ok;
}

/// Commits a staged timeline with an optimistic-concurrency check.
///
/// The draft records the committed row's `updatedAt` when editing began. If the
/// row's `updatedAt` changed since then — it was edited from another surface —
/// the apply is refused so the newer committed data is not silently clobbered.
/// A missing row counts as a change too (the timeline was deleted).
Future<MappingApplyOutcome> applyStagedMappingTimeline({
  required BackgroundMappingTimeline staged,
  required DateTime? baselineUpdatedAt,
  BackgroundMappingRepository? repo,
}) async {
  final r = repo ?? DbModule.bgMappingRepo;

  BackgroundMappingTimeline? latest;
  try {
    latest = await r.getTimelineForFg(
      storageId: staged.storageId,
      path: staged.path,
    );
  } catch (e) {
    return MappingApplyOutcome(MappingApplyStatus.writeFailed, '$e');
  }

  if (latest?.updatedAt != baselineUpdatedAt) {
    return const MappingApplyOutcome(MappingApplyStatus.conflict);
  }

  try {
    await r.saveTimeline(
      storageId: staged.storageId,
      path: staged.path,
      fgTotalMs: staged.fgTotalMs ?? latest?.fgTotalMs,
      segments: staged.segments,
    );
  } on MappingValidationError catch (e) {
    return MappingApplyOutcome(MappingApplyStatus.invalid, e.message);
  } catch (e) {
    return MappingApplyOutcome(MappingApplyStatus.writeFailed, '$e');
  }
  return const MappingApplyOutcome(MappingApplyStatus.ok);
}
