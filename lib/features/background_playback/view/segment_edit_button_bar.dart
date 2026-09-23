import 'package:flutter/material.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/background_playback/resolver/segment_span_math.dart';
import 'package:iris/features/background_playback/rule/segment_color.dart';
import 'package:iris/features/background_playback/view/control_target_indicator.dart';
import 'package:iris/features/background_playback/view/segment_volume_distribution.dart';
import 'package:iris/features/virtual_media/interaction/controller/foreground_window_resolver.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/control_bar/control_bar_widgets/control_bar_constants.dart';
import 'package:iris/pages/player/control_bar/control_bar_widgets/seek_step_popover.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/a11y_tooltip.dart';
import 'package:provider/provider.dart';

/// Whether the P "move to current" button is shown in the align editor bar.
///
/// P's move-to-current aligns the 副音 cursor onto the foreground cursor, which
/// is being reworked. The button is intentionally DISABLED for now while every
/// implementation is retained: [onMoveP]/[canMoveP] below, the panel's
/// `movePointToCurrent(SegmentPoint.p)`, and [SegmentSpanMath.movePointTo]'s
/// `SegmentPoint.p` case. Flip this to `true` to restore the button — do NOT
/// delete the code.
const bool kEnablePMoveButton = false;

/// Bottom action bar of the align editor.
///
/// Same visual language as the normal control bar (shared button widgets and
/// icon size) so replacing the bar does not change the look. A `Wrap` keeps it
/// from overflowing on a 360px-wide phone where the controls cannot fit on one
/// line.
class SegmentEditButtonBar extends StatelessWidget {
  const SegmentEditButtonBar({
    super.key,
    required this.isPlaying,
    required this.onPlayPause,
    required this.onBackward,
    required this.onForward,
    required this.snapOn,
    required this.onToggleSnap,
    required this.onSave,
    required this.onExit,
    required this.isDisplayingBg,
    required this.onToggleDisplay,
    required this.abCenterMs,
    required this.onMoveA,
    required this.onMoveB,
    required this.canMoveP,
    required this.onMoveP,
    required this.silenceOn,
    required this.onToggleSilence,
    this.busy = false,
    this.onSwapRings,
    this.colorArgb,
    this.onPickColor,
    this.color,
    this.overlayColor,
  });

  final bool isPlaying;
  final VoidCallback onPlayPause;
  final VoidCallback onBackward;
  final VoidCallback onForward;

  /// Snap-to-saved-boundary (卡值） mode: A / P / B stop exactly at saved
  /// segment boundaries like at the 0% / 100% ends. Toggled by the host, which
  /// owns the persisted setting and the first-use guide.
  final bool snapOn;
  final VoidCallback onToggleSnap;
  final VoidCallback onSave;
  final VoidCallback onExit;

  /// Which engine's picture the video surface shows.
  final bool isDisplayingBg;
  final VoidCallback onToggleDisplay;

  /// The A/B move-to-current buttons: one per endpoint. Each stays a stable
  /// instance handed to the per-tick timeline, so the live position
  /// subscription lives in a LEAF inside the button (see [_MovePointButton]),
  /// not here. `abCenterMs` is the draft span's centre; the endpoint whose move
  /// the A<P<B rule forbids from the current playhead is greyed.
  final int? abCenterMs;
  final VoidCallback onMoveA;
  final VoidCallback onMoveB;

  /// Move P to the current playhead — its own button (P is always movable).
  /// Currently hidden behind [kEnablePMoveButton]; retained for a future
  /// re-enable.
  final bool canMoveP;
  final VoidCallback onMoveP;

  /// The saved-as-silence toggle state (draft action), applied on Save.
  final bool silenceOn;
  final VoidCallback onToggleSilence;

  /// A commit (save / exit-discard confirm) is in flight — persist/exit actions
  /// are disabled so a fast double-tap cannot fire two saves.
  final bool busy;

  /// Segment label colour (ARGB) and its picker entry point. Null callback
  /// hides the control (e.g. before a draft is seeded).
  final int? colorArgb;
  final VoidCallback? onPickColor;

  /// Side type only: flip which physical ring drives the foreground video.
  final VoidCallback? onSwapRings;
  final Color? color;
  final WidgetStateProperty<Color?>? overlayColor;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final seekStep =
        useAppStore().select(context, (s) => s.seekStepSeconds);
    final theme = Theme.of(context);

    return Padding(
      // Same horizontal inset as the normal bottom bar's Wrap, so the two bars
      // occupy the same footprint when the panel swaps them.
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Wrap(
      key: const ValueKey('segment_edit_button_bar'),
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      // Same Wrap metrics as the normal bottom bar (spacing 8 / runSpacing 6):
      // the APB bar must measure the same, or the dial's slot would shift.
      spacing: 8,
      runSpacing: 6,
      children: [
        _iconButton(
          context,
          key: const ValueKey('segment_edit_back'),
          tooltip: t.gesture_action_seek_backward,
          icon: Icons.replay_10_rounded,
          onPressed: onBackward,
        ),
        _iconButton(
          context,
          key: const ValueKey('segment_edit_play_pause'),
          tooltip: isPlaying ? t.pause : t.play,
          icon: isPlaying
              ? Icons.pause_rounded
              : Icons.play_arrow_rounded,
          onPressed: onPlayPause,
        ),
        _iconButton(
          context,
          key: const ValueKey('segment_edit_forward'),
          tooltip: t.gesture_action_seek_forward,
          icon: Icons.forward_10_rounded,
          onPressed: onForward,
        ),
        // Seek step adjuster — reuses the control bar's popover.
        a11yTooltip(
          context: context,
          message: '${t.menu_seek_step} (${seekStep}s)',
          child: TextButton(
            onPressed: () => showSeekStepPopover(context),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              minimumSize: const Size(40, 36),
            ),
            child: Text(
              '${seekStep}s',
              style: theme.textTheme.labelMedium,
            ),
          ),
        ),
        // Volume distribution — a seek-step-style anchored popover, so the
        // bar's own layout is untouched.
        _iconButton(
          context,
          key: const ValueKey('segment_edit_volume'),
          tooltip: t.bg_align_volume_distribute,
          icon: Icons.tune_outlined,
          onPressed: () => showSegmentVolumePopover(context),
        ),
        if (onPickColor != null) _colorButton(context),
        // Snap-to-saved-boundary (卡值） toggle (replaces the retired overlap
        // strategy picker): persistence + first-use guide live in the host.
        _iconButton(
          context,
          key: const ValueKey('segment_snap_button'),
          tooltip: t.bg_align_snap_tooltip,
          icon: Icons.center_focus_strong_rounded,
          active: snapOn,
          onPressed: onToggleSnap,
        ),
        if (onSwapRings != null)
          _iconButton(
            context,
            key: const ValueKey('segment_edit_swap_rings'),
            tooltip: t.bg_align_swap_rings,
            icon: Icons.swap_vert_rounded,
            onPressed: onSwapRings!,
          ),
        // Which picture the surface shows (fg / bg) — independent of controls.
        _iconButton(
          context,
          key: const ValueKey('segment_edit_display_target'),
          tooltip: isDisplayingBg ? t.bg_display_to_fg : t.bg_display_to_bg,
          icon: isDisplayingBg
              ? Icons.smart_display_rounded
              : Icons.smart_display_outlined,
          active: isDisplayingBg,
          onPressed: onToggleDisplay,
        ),
        // One move-to-current button per endpoint; the endpoint the A<P<B rule
        // forbids from the current playhead is greyed by the leaf.
        _MovePointButton(
          key: const ValueKey('segment_edit_move_a'),
          point: SegmentPoint.a,
          centerMs: abCenterMs,
          tooltip: t.bg_align_move_a_here,
          onPressed: onMoveA,
          color: color,
        ),
        _MovePointButton(
          key: const ValueKey('segment_edit_move_b'),
          point: SegmentPoint.b,
          centerMs: abCenterMs,
          tooltip: t.bg_align_move_b_here,
          onPressed: onMoveB,
          color: color,
        ),
        // P move-to-current is intentionally disabled (see
        // [kEnablePMoveButton]); the code is retained, not deleted.
        if (kEnablePMoveButton)
          _pointButton(
            context,
            key: const ValueKey('segment_edit_move_p'),
            label: 'P',
            tooltip: t.bg_align_move_p_here,
            enabled: canMoveP,
            onPressed: onMoveP,
          ),
        // Saved-as-silence is a STATE toggle: it flips the draft's action only;
        // the Save button performs the actual write.
        _iconButton(
          context,
          key: const ValueKey('segment_edit_save_silent'),
          tooltip: t.bg_align_silence_no_file,
          icon: Icons.volume_off_rounded,
          active: silenceOn,
          enabled: !busy,
          onPressed: onToggleSilence,
        ),
        _iconButton(
          context,
          key: const ValueKey('segment_edit_save'),
          tooltip: t.bg_align_save,
          icon: Icons.check_rounded,
          active: true,
          enabled: !busy,
          onPressed: onSave,
        ),
        _iconButton(
          context,
          key: const ValueKey('segment_edit_exit'),
          tooltip: t.bg_align_exit_no_save,
          icon: Icons.close_rounded,
          enabled: !busy,
          onPressed: onExit,
        ),
      ],
      ),
    );
  }

  Widget _iconButton(
    BuildContext context, {
    required Key key,
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
    bool active = false,
    bool enabled = true,
  }) {
    return KeyedSubtree(
      key: key,
      child: a11yTooltipIconButton(
        context: context,
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        icon: Icon(
          icon,
          size: kIconSizeSecondary,
          color: active ? kBackgroundTargetColor : color,
        ),
        onPressed: enabled ? onPressed : null,
        style: ButtonStyle(overlayColor: overlayColor),
      ),
    );
  }

  /// A single swatch button that opens the segment colour picker.
  Widget _colorButton(BuildContext context) {
    final t = getLocalizations(context);
    final theme = Theme.of(context);
    final argb = colorArgb ?? kSegmentColorDefaultArgb;
    return KeyedSubtree(
      key: const ValueKey('segment_edit_color'),
      child: a11yTooltip(
        context: context,
        message: t.bg_segment_color,
        child: TextButton(
          onPressed: onPickColor,
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            minimumSize: const Size(40, 36),
            padding: const EdgeInsets.symmetric(horizontal: 6),
          ),
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: Color(normalizeSegmentColorArgb(argb)),
              shape: BoxShape.circle,
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
          ),
        ),
      ),
    );
  }

  /// The "move to current" button: a compact letter, greyed (and inert) when
  /// the A<P<B rule forbids that move from the current playhead.
  Widget _pointButton(
    BuildContext context, {
    required Key key,
    required String label,
    required String tooltip,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return KeyedSubtree(
      key: key,
      child: _letterButton(
        context,
        label: label,
        tooltip: tooltip,
        enabled: enabled,
        onPressed: onPressed,
        color: color,
      ),
    );
  }
}

/// The shared "move to current" letter button: a compact letter, greyed (and
/// inert) while the A<P<B rule forbids the move from the current playhead.
Widget _letterButton(
  BuildContext context, {
  required String label,
  required String tooltip,
  required bool enabled,
  required VoidCallback onPressed,
  Color? color,
}) {
  return a11yTooltip(
    context: context,
    message: tooltip,
    child: TextButton(
      onPressed: enabled ? onPressed : null,
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        minimumSize: const Size(32, 36),
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: enabled
                  ? (color ?? Theme.of(context).colorScheme.primary)
                  : Theme.of(context).disabledColor,
              fontWeight: FontWeight.w700,
            ),
      ),
    ),
  );
}

/// A single endpoint's "move to current" button (A or B).
///
/// The illegal endpoint is greyed here from the live playhead: A is movable
/// while the playhead lies left of the span centre, B while it lies right of it
/// (see [SegmentSpanMath.canMovePoint]).
///
/// This is a LEAF position subscription on purpose — [SegmentEditButtonBar] is
/// handed down as a stable instance (the editor's timeline rebuilds per tick),
/// so the per-tick select must live here or the whole bar would rebuild.
class _MovePointButton extends StatelessWidget {
  const _MovePointButton({
    super.key,
    required this.point,
    required this.centerMs,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final SegmentPoint point;
  final int? centerMs;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    // Same physical (VM-undone) fg position the press-time action resolves.
    final int fgMs = context.select<MediaPlayer, int>(
      (p) => foregroundWindowNow(
        playerDurationMs: p.duration.inMilliseconds,
        playerPositionMs: p.position.inMilliseconds,
      ).positionMs,
    );
    final bool enabled = centerMs != null &&
        SegmentSpanMath.canMovePoint(
          point: point,
          fgMs: fgMs,
          centerMs: centerMs!,
        );
    return _letterButton(
      context,
      label: point == SegmentPoint.a ? 'A' : 'B',
      tooltip: tooltip,
      enabled: enabled,
      onPressed: onPressed,
      color: color,
    );
  }
}
