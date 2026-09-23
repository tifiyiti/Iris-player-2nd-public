import 'package:flutter/material.dart';
import 'package:iris/utils/format_duration_to_minutes.dart';
import 'package:iris/utils/get_localizations.dart';

/// Floating preview for cross-segment drag (spec §6).
///
/// Shows where the release will land without changing the picture until
/// finger lift. Text comes from ARB placeholders (never concatenation) and
/// ellipsizes inside a width cap so 360px phones never overflow.
class VmDragPreviewOverlay extends StatelessWidget {
  const VmDragPreviewOverlay({
    super.key,
    required this.segIndex,
    required this.segCount,
    required this.segName,
    required this.localPos,
    required this.segDur,
    required this.virtualPos,
    required this.totalDur,
  });

  final int segIndex;
  final int segCount;
  final String segName;
  final Duration localPos;
  final Duration segDur;
  final Duration virtualPos;
  final Duration totalDur;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final text = t.vm_drag_preview(
      segIndex + 1,
      segCount,
      segName,
      formatDurationToMinutes(localPos),
      formatDurationToMinutes(segDur),
      formatDurationToMinutes(virtualPos),
      formatDurationToMinutes(totalDur),
    );
    final maxWidth = MediaQuery.sizeOf(context).width - 48;
    return Material(
      color: Colors.black.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth.clamp(160.0, 320.0)),
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 12)),
        ),
      ),
    );
  }
}
