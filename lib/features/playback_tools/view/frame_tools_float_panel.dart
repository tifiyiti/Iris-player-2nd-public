import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/playback_tools/store/playback_tools_store.dart';
import 'package:iris/features/playback_tools/view/frame_step_button.dart';
import 'package:iris/features/playback_tools/view/screenshot_capture_flow.dart';
import 'package:iris/features/playback_tools/view/screenshot_feedback.dart';
import 'package:iris/models/player.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/a11y_tooltip.dart';
import 'package:provider/provider.dart';

/// Draggable frame-tools float panel (phone): frame step pair + screenshot
/// shutter. Opened from the player more-menu; lives in the player Stack so
/// it survives control-bar auto-hide and menu closes.
///
/// The remembered spot is stored as a FRACTION of the host's available travel
/// (AppState.frameToolsPanelFraction), never as pixels. An absolute offset
/// drifts the moment the window grows: a panel parked in the corner keeps its
/// old pixel offset and stops being corner-anchored. Re-deriving pixels from a
/// fraction on every build makes the same spot survive resize, rotation,
/// fullscreen and restart alike.
///
/// Contract: every build path returns a Positioned (see hidden branch) —
/// the hosting player Stack sizes itself via constraints.biggest only
/// while it stays all-positioned.
class FrameToolsFloatPanel extends HookWidget {
  const FrameToolsFloatPanel({super.key});

  @override
  Widget build(BuildContext context) {
    // All hooks BEFORE any early return: toggling visibility must keep a
    // stable hook order or flutter_hooks throws on the hide rebuild.
    final visible =
        usePlaybackToolsStore().select(context, (s) => s.frameToolsVisible);
    // Read directly rather than through `select`: only this panel's own drag
    // moves the spot, and the widget-test harness cannot deliver select
    // notifications under FakeAsync anyway.
    final Offset remembered = useAppStore().state.frameToolsPanelFraction;
    // Live fraction while the panel is up; null until the first drag, which
    // means "use `remembered`".
    final frac = useState<Offset?>(null);
    // Bumped once per post-frame placement so a resize always repaints
    // against the freshly measured host — a fraction is only meaningful
    // relative to the size it is applied to.
    final layoutTick = useState(0);
    final shutterFlash = useState(false);
    final viewport = MediaQuery.sizeOf(context);

    /// Live size of the HOSTING STACK (walks up past the panel's own
    /// Positioned): the player Stack ≈ video area and is the container drags
    /// are clamped against. Measured on demand so a resize can never leave the
    /// clamp bound to a stale size.
    Size? hostStackSize() {
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return null;
      RenderBox? node =
          box.parent is RenderBox ? box.parent as RenderBox : null;
      while (node != null && node is! RenderStack) {
        node = node.parent is RenderBox ? node.parent as RenderBox : null;
      }
      return node?.size;
    }

    Size panelSize() {
      final box = context.findRenderObject();
      return box is RenderBox && box.hasSize ? box.size : Size.zero;
    }

    /// Pixels of travel the fraction is spread across.
    Size travel() {
      final host = hostStackSize() ?? MediaQuery.sizeOf(context);
      final panel = panelSize();
      return Size(
        (host.width - panel.width).clamp(0.0, double.maxFinite).toDouble(),
        (host.height - panel.height).clamp(0.0, double.maxFinite).toDouble(),
      );
    }

    // Sizes only exist after layout, and the reveal happens on a rebuild the
    // frame BEFORE that layout lands — so adopt the stored fraction (or fall
    // back to the centred default) and repaint once the boxes are real. The
    // same effect handles every viewport change, which is precisely what the
    // old absolute offset failed to do.
    useEffect(() {
      if (!visible) return null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!visible) return;
        frac.value = frac.value ?? remembered;
        // Always bump: an identical value would not notify, and a fresh size
        // is exactly what this rebuild exists to pick up.
        layoutTick.value = layoutTick.value + 1;
      });
      return null;
    }, [visible, viewport]);

    if (!visible) {
      // Hidden state must remain a POSITIONED child of the hosting Stack.
      //
      // RenderStack._computeSize sizes a Stack that has ANY non-positioned
      // child to its largest non-positioned child (under loose constraints);
      // only an ALL-positioned Stack takes constraints.biggest. The player
      // Stack is otherwise all-positioned, so returning a bare
      // SizedBox.shrink() here made THIS widget the sole non-positioned
      // child — the entire player subtree laid out at Size.zero and the app
      // rendered as a black screen (Windows + Android), while audio/input
      // kept working because hit-testing/keyboard focus are size-independent.
      return const Positioned(left: 0, top: 0, child: SizedBox.shrink());
    }

    // Fraction currently in force: a drag in progress wins over the stored
    // spot, which is what makes the very first frame land where it belongs.
    final Offset fraction = frac.value ?? remembered;
    final Size span = travel();
    final double left = fraction.dx.clamp(0.0, 1.0) * span.width;
    final double top = fraction.dy.clamp(0.0, 1.0) * span.height;

    void commit() {
      final Offset? current = frac.value;
      if (current == null) return; // never dragged: nothing new to remember
      // ignore: discarded_futures
      useAppStore().updateFrameToolsPanelFraction(current);
    }

    Future<void> capture() async {
      // Navigator captured BEFORE the await so the feedback dialog survives
      // player-page rebuilds while the shutter runs.
      final navigator = Navigator.of(context, rootNavigator: true);
      final t = getLocalizations(context);
      final player = context.read<MediaPlayer>();
      final result = await runScreenshotCapture(
        navigator: navigator,
        player: player,
        savingLabel: t.shot_saving,
        onBusyChanged: (busy) => shutterFlash.value = busy,
      );
      await showScreenshotFeedback(navigator, result);
    }

    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onPanUpdate: (details) {
          // Drag frames stay memory-only: one DB write per gesture, not one
          // per pixel (Drift runs on the UI isolate).
          final Size span = travel();
          final Offset base = frac.value ?? remembered;
          frac.value = Offset(
            (base.dx + (span.width <= 0 ? 0 : details.delta.dx / span.width))
                .clamp(0.0, 1.0)
                .toDouble(),
            (base.dy + (span.height <= 0 ? 0 : details.delta.dy / span.height))
                .clamp(0.0, 1.0)
                .toDouble(),
          );
        },
        onPanEnd: (_) => commit(),
        onPanCancel: commit,
        child: Material(
          key: const ValueKey('frame_tools_panel'),
          elevation: 6,
          borderRadius: BorderRadius.circular(24),
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.92),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FrameStepButton(
                  forward: false,
                  tooltip: getLocalizations(context).shot_frame_prev,
                  icon: Icons.skip_previous_rounded,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                a11yTooltipIconButton(
                  context: context,
                  // AXTree stability (#182444): tap-only under a UIA client.
                  tooltip: getLocalizations(context).shot_frame_capture,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.camera_alt_rounded,
                    color: shutterFlash.value
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  onPressed: capture,
                ),
                FrameStepButton(
                  forward: true,
                  tooltip: getLocalizations(context).shot_frame_next,
                  icon: Icons.skip_next_rounded,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                a11yTooltipIconButton(
                  context: context,
                  tooltip: getLocalizations(context).close,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: usePlaybackToolsStore().hideFrameTools,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
