import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/windows/desktop_keyboard/store/key_sequence_buffer_store.dart';

/// Waiting indicator shown while a `;` prefix sequence is armed (SRS §4).
///
/// Mounted unconditionally in the player Stack (GestureTipsOverlay pattern):
/// with buffering off it renders nothing, so legacy schemes and idle states
/// pay zero visual/behavioral cost.
class KeySequenceOverlay extends HookWidget {
  const KeySequenceOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final isBuffering = useKeySequenceBufferStore()
        .select(context, (state) => state.isBuffering);
    if (!isBuffering) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    // Windows AXTree-crash mitigation (#103808 family): transient indicator,
    // zero announceable content — keep it out of the accessibility bridge's
    // update pipeline entirely.
    return ExcludeSemantics(
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 48),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    ';',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'waiting for key…  (F H R X)',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
