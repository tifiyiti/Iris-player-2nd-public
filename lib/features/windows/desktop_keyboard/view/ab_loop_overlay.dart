import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/windows/desktop_keyboard/store/ab_loop_store.dart';

/// Tiny indicator for the armed A-B loop (bottom-left chip).
///
/// Mounted unconditionally in the player Stack; renders nothing while the
/// loop is off (GestureTipsOverlay pattern — zero cost when unused).
class AbLoopOverlay extends HookWidget {
  const AbLoopOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final state = useAbLoopStore().select(context, (s) => s);
    if (!state.enabled || state.pointA == null || state.pointB == null) {
      return const SizedBox.shrink();
    }
    final colorScheme = Theme.of(context).colorScheme;
    String fmt(Duration d) {
      final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
      return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
    }

    // Windows AXTree-crash mitigation (#103808 family): transient indicator,
    // zero announceable content — keep it out of the accessibility bridge's
    // update pipeline entirely.
    return ExcludeSemantics(
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 96),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colorScheme.primary),
              ),
              child: Text(
                'A ${fmt(state.pointA!)} ↔ B ${fmt(state.pointB!)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
