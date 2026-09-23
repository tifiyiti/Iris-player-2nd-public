import 'package:flutter/material.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/a11y_tooltip.dart';

/// Non-modal draggable card shell for popups that live in a host Stack (e.g.
/// the 副音 quick panels over the video surface).
///
/// Unlike a modal `showDialog`, nothing is dimmed and the surface underneath
/// stays interactive. Dragging is owned by the HEADER only: the body may hold
/// vertical sliders / scrollable lists whose gestures must never be stolen by
/// the card (a parent pan here would fight them in the gesture arena).
class DraggableFloatingCard extends StatelessWidget {
  const DraggableFloatingCard({
    super.key,
    required this.title,
    required this.onClose,
    required this.onDragDelta,
    required this.width,
    required this.height,
    required this.child,
  });

  final String title;
  final VoidCallback onClose;
  final ValueChanged<Offset> onDragDelta;
  final double width;
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = getLocalizations(context);
    return Material(
      key: const ValueKey('draggable_floating_card'),
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.95),
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    label: t.bg_quick_panel_drag,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: (details) => onDragDelta(details.delta),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.drag_indicator_rounded,
                              size: 20,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                a11yTooltipIconButton(
                  context: context,
                  tooltip: t.close,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: onClose,
                ),
                const SizedBox(width: 4),
              ],
            ),
            const Divider(height: 1),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
