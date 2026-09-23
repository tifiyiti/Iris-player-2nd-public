import 'package:iris/features/virtual_media/model/domain/vm_item.dart';

/// 副音 (bg) playback runs on REAL single files only — its queue never
/// participates in virtual-merge grouping. While the shared controls target the
/// bg engine, the foreground's virtual session must therefore not decorate the
/// bg scrubber (no segment boundaries, no red spans, no block partition).
///
/// Kept as a pure function so the "bg target suppresses VM" rule is testable
/// without a widget tree and is applied identically by every progress surface.
VirtualMediaItem? vmItemForControlTarget(
  VirtualMediaItem? item, {
  required bool bgIsControl,
}) =>
    bgIsControl ? null : item;

/// Whether a progress surface may paint virtual-media marks / blocks.
bool showVmScrubberMarks({
  required bool vmItemPresent,
  required bool bgIsControl,
}) =>
    vmItemPresent && !bgIsControl;
