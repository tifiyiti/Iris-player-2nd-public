import 'package:iris/features/virtual_media/model/domain/vm_item.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.mediaProbe);

/// Why a would-be virtual group cannot play as one merged video.
///
/// A group is feasible only when EVERY segment carries a known positive
/// duration from the database. A single feasible segment is still a valid
/// virtual item: the middle layer maps it 1:1 and the player feeds it as an
/// ordinary single file, so no special-casing is needed downstream.
enum VmFailReason {
  /// Group has no segments at all.
  emptyGroup,

  /// At least one segment has null/zero duration — the virtual timeline
  /// cannot be built (`prefixMs` would collapse it to 0).
  zeroDuration,

  /// Library row vanished between resolve and play.
  missingNode,

  /// Duration probe yielded nothing usable.
  probeFailed,

  /// Blocking preflight exceeded its time budget (treated as a bug).
  timeout,
}

/// Failure attribution for one unmergeable segment.
///
/// [detail] is legacy free text (kept for log/test compat); UI must render
/// from the structured fields instead: [reason] selects the message template
/// and [badNames] / [errorText] fill it in (see `vm_fail_*` l10n keys).
class VmFailInfo {
  final VmFailReason reason;
  final String detail;

  /// Names of the unknown-duration members of the failed group (only set for
  /// group-wide zero-duration failures so the tooltip can name them).
  final List<String> badNames;

  /// Raw error text for read failures (verify-error path only).
  final String? errorText;
  final String scopeKey;
  final String ruleId;

  const VmFailInfo({
    required this.reason,
    required this.detail,
    this.badNames = const [],
    this.errorText,
    required this.scopeKey,
    required this.ruleId,
  });
}

/// Result of splitting resolved groups into playable vs degraded.
class VmPartition {
  final List<VirtualMediaItem> valid;
  final Map<String, VmFailInfo> failByKey;

  /// The infeasible groups themselves (single-segment-feasible excluded —
  /// those are valid). Kept so the scan flow can re-probe exactly the failed
  /// segments without re-deriving them from keys.
  final List<VirtualMediaItem> failed;

  const VmPartition({
    required this.valid,
    required this.failByKey,
    this.failed = const [],
  });
}

/// Localized tooltip for a preflight-degraded list tile.
///
/// Renders from the structured fields ([VmFailInfo.reason] + [badNames] /
/// [errorText]); the legacy [VmFailInfo.detail] free text is never shown.
String vmFailTooltip(VmFailInfo info, AppLocalizations t) {
  switch (info.reason) {
    case VmFailReason.zeroDuration:
      if (info.badNames.isNotEmpty) {
        return t.vm_fail_group_zero(info.badNames.join(', '));
      }
      return t.vm_fail_zero_duration;
    case VmFailReason.missingNode:
      if (info.errorText != null) {
        return t.vm_fail_verify_error(info.errorText!);
      }
      return t.vm_fail_missing_node;
    case VmFailReason.probeFailed:
      return t.vm_fail_zero_duration;
    case VmFailReason.timeout:
    case VmFailReason.emptyGroup:
      return t.vm_fail_degraded;
  }
}

/// One segment is feasible when its duration is known and positive.
bool isVmSegmentFeasible(VirtualSegment seg) =>
    seg.durationMs != null && seg.durationMs! > 0;

/// Splits [items] into feasible virtual groups vs per-segment failures.
///
/// - Single-segment feasible groups are VALID (not failures).
/// - A group with ANY infeasible segment fails AS A WHOLE: every member is
///   recorded in [VmPartition.failByKey] so the overlay leaves them as
///   ordinary single items with a yellow warning mark.
/// - Pure function over DB-sourced durations; never touches the filesystem.
VmPartition partitionVmItems(List<VirtualMediaItem> items) {
  final valid = <VirtualMediaItem>[];
  final failed = <VirtualMediaItem>[];
  final failByKey = <String, VmFailInfo>{};
  for (final item in items) {
    if (item.segments.isEmpty) {
      _log.w('[vm-preflight] scope=${item.scopeKey} rule=${item.ruleId} '
          'reason=emptyGroup: no segments, degraded to normal list');
      failed.add(item);
      continue;
    }
    final bad =
        item.segments.where((s) => !isVmSegmentFeasible(s)).toList();
    if (bad.isEmpty) {
      valid.add(item);
      continue;
    }
    failed.add(item);
    final badNameList = [for (final b in bad) b.name];
    for (final s in item.segments) {
      final feasible = isVmSegmentFeasible(s);
      failByKey[s.mediaKey] = VmFailInfo(
        reason: VmFailReason.zeroDuration,
        detail: feasible
            ? 'group merge failed: unknown-duration members (${badNameList.join(', ')}), degraded to normal playback'
            : 'unknown duration (no duration in database), cannot join virtual merge, degraded to normal playback',
        // Name the culprits on the culprit rows so tooltips point at the
        // real bad files; feasible members keep the full bad-name list.
        badNames: feasible ? badNameList : [s.name],
        scopeKey: item.scopeKey,
        ruleId: item.ruleId,
      );
    }
    // Sample-only logging: full key lists for 100+ segment groups spammed
    // the log on every resolve pass.
    final sample = bad.take(3).map((b) => b.mediaKey).join(',');
    final more = bad.length > 3 ? ' +${bad.length - 3} more' : '';
    _log.w('[vm-preflight] scope=${item.scopeKey} rule=${item.ruleId} '
        'reason=zeroDuration bad=$sample$more '
        'segments=${item.segments.length}: degraded to normal list');
  }
  return VmPartition(valid: valid, failByKey: failByKey, failed: failed);
}
