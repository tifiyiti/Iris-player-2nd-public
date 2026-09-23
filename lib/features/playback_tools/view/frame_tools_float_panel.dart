import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/playback_tools/services/screenshot_service.dart';
import 'package:iris/features/playback_tools/store/playback_tools_store.dart';
import 'package:iris/features/playback_tools/view/screenshot_feedback.dart';
import 'package:iris/features/playback_tools/view/frame_step_button.dart';
import 'package:iris/models/player.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/a11y_tooltip.dart';
import 'package:provider/provider.dart';

/// Draggable frame-tools float panel (phone): frame step pair + screenshot
/// shutter. Opened from the player more-menu; lives in the player Stack so
/// it survives control-bar auto-hide and menu closes.
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
    // null = not yet placed; first placement is horizontally centered
    // (measured post-frame), afterwards drags move it for the whole session.
    final offset = useState<Offset?>(null);
    final shutterFlash = useState(false);

    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (offset.value != null) return;
        final box = context.findRenderObject();
        if (box is! RenderBox || !box.hasSize) return;
        // Center within the HOSTING STACK (walks up past the panel's own
        // Positioned), not the screen: the player Stack ≈ video area and is
        // the container drags are clamped against.
        RenderBox? node = box.parent is RenderBox ? box.parent as RenderBox : null;
        while (node != null && node is! RenderStack) {
          node = node.parent is RenderBox ? node.parent as RenderBox : null;
        }
        final hostWidth = node?.size.width ?? MediaQuery.of(context).size.width;
        offset.value = Offset(
          (hostWidth - box.size.width) / 2,
          120.0,
        );
      });
      return null;
    }, const []);

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
    // Before the measured placement lands (one frame), park at the legacy
    // spot so the real card is on stage for the post-frame measurement.
    final placed = offset.value ?? const Offset(16.0, 120.0);

    Future<void> capture() async {
      // Navigator captured BEFORE the await so the feedback dialog survives
      // player-page rebuilds while the shutter runs.
      final navigator = Navigator.of(context, rootNavigator: true);
      final t = getLocalizations(context);
      final player = context.read<MediaPlayer>();
      shutterFlash.value = true;
      // Immediate progress + hard timeout: the first-ever capture stacks
      // permission dialogs, public-dir mkdir and a cold mpv frame grab.
      // Without feedback the shutter looks frozen (no dialog appears until
      // the whole chain finishes); without a timeout a stuck grab hangs
      // forever. Both now degrade to the normal feedback dialog.
      BuildContext? progressContext;
      var progressOpen = false;
      var captureDone = false;
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 400), () {
          if (captureDone) return;
          if (!navigator.mounted || !shutterFlash.value) return;
          progressOpen = true;
          showDialog<void>(
            context: navigator.context,
            barrierDismissible: false,
            builder: (context) {
              progressContext = context;
              return AlertDialog(
                content: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(width: 16),
                    Text(getLocalizations(context).shot_saving),
                  ],
                ),
              );
            },
          ).then((_) => progressOpen = false);
        }),
      );
      ScreenshotResult result;
      try {
        result = await captureCurrentFrame(
          player,
        ).timeout(const Duration(seconds: 15));
      } on TimeoutException {
        result = ScreenshotFailure(t.shot_timeout);
      } finally {
        captureDone = true;
        shutterFlash.value = false;
        if (progressOpen &&
            progressContext != null &&
            progressContext!.mounted) {
          Navigator.pop(progressContext!);
        }
      }
      await showScreenshotFeedback(navigator, result);
    }

    return Positioned(
      left: placed.dx,
      top: placed.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          final base = offset.value;
          if (base == null) return;
          offset.value = Offset(
            (base.dx + details.delta.dx).clamp(0, double.maxFinite),
            (base.dy + details.delta.dy).clamp(0, double.maxFinite),
          );
        },
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
