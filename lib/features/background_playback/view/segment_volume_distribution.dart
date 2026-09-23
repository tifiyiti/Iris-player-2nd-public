import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/background_playback/model/domain/segment_edit_draft.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/features/background_playback/view/segment_edit_context.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:popover/popover.dart';

/// Opens the volume-distribution editor as a small anchored popover, mirroring
/// the seek-step popover: it never touches the surrounding layout (nothing is
/// inserted into the panel), stays non-modal, and closes on an outside tap.
Future<void> showSegmentVolumePopover(BuildContext context) async {
  final size = MediaQuery.sizeOf(context);
  await showPopover(
    context: context,
    bodyBuilder: (context) => const Material(
      type: MaterialType.transparency,
      child: SegmentVolumeDistributionPanel(),
    ),
    direction: PopoverDirection.top,
    width: math.min(320.0, size.width - 24),
    height: math.min(176.0, size.height - 24),
    arrowHeight: 0,
    arrowWidth: 0,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.transparent,
  );
}

/// Volume-split editor body of the align editor's popover.
///
/// Three sliders, all editing the CURRENT edit session:
/// - foreground share (%) — written to the draft segment, with an independent
///   前景 mute,
/// - 副音 share (%) — written to the draft segment (0% keeps the file but
///   silences 副音 for the span), with an independent 副音 mute,
/// - the real master volume — the SAME global value normal playback uses, with
///   the app-wide mute.
class SegmentVolumeDistributionPanel extends HookWidget {
  const SegmentVolumeDistributionPanel({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final bg = useBackgroundPlaybackStore();
    // The ratio lives on the DRAFT being edited (not a store-wide "last used"
    // value), so a fresh segment always starts at the 30/100 default and an
    // existing one shows its own saved share.
    final ctx = useSegmentEditContext(context);
    final draft = ctx.draft;
    final fgPercent = draft?.fgPercent ?? kDefaultSegmentFgPercent;
    final bgPercent = draft?.bgPercent ?? kDefaultSegmentBgPercent;

    void setRatio({int? fgPercent, int? bgPercent}) {
      final d = ctx.draft;
      if (d == null) return;
      bg.updateSegmentEditDraft(d.copyWith(
        fgPercent: fgPercent,
        bgPercent: bgPercent,
      ));
    }

    final fgMuted = bg.select(context, (s) => s.fgMuted);
    final bgMuted = bg.select(context, (s) => s.bgMuted);
    final app = useAppStore();
    final volume = app.select(context, (s) => s.volume);
    final muted = app.select(context, (s) => s.isMuted);
    final textStyle = Theme.of(context).textTheme.labelSmall;

    return Container(
      key: const ValueKey('segment_volume_distribution'),
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _row(
            context,
            label: t.bg_align_ratio_fg,
            value: fgPercent.toDouble(),
            max: 100,
            valueText: '$fgPercent%',
            muted: fgMuted,
            muteTooltip: t.bg_align_ratio_fg_mute,
            onToggleMute: bg.toggleFgMute,
            onChanged: (v) => setRatio(fgPercent: v.round()),
          ),
          _row(
            context,
            label: t.bg_align_ratio_bg,
            value: bgPercent.toDouble(),
            max: 100,
            valueText: '$bgPercent%',
            muted: bgMuted,
            muteTooltip: t.bg_align_ratio_bg_mute,
            onToggleMute: bg.toggleBgMute,
            onChanged: (v) => setRatio(bgPercent: v.round()),
          ),
          _row(
            context,
            label: t.bg_align_master_volume,
            value: (muted ? 0 : volume).toDouble(),
            max: 100,
            valueText: '$volume',
            muted: muted,
            muteTooltip: t.bg_align_master_mute,
            onToggleMute: () => app.updateMute(!muted),
            onChanged: (v) {
              if (muted) app.updateMute(false);
              app.updateVolume(v.round());
            },
          ),
          const SizedBox(height: 2),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              t.bg_align_volume_distribute,
              style: textStyle?.copyWith(
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required String label,
    required double value,
    required double max,
    required String valueText,
    required bool muted,
    required String muteTooltip,
    required VoidCallback onToggleMute,
    required ValueChanged<double> onChanged,
  }) {
    final style = Theme.of(context).textTheme.labelSmall;
    final iconColor = muted ? Theme.of(context).disabledColor : null;
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: value.clamp(0, max),
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            valueText,
            textAlign: TextAlign.right,
            style: style,
          ),
        ),
        SizedBox(
          width: 32,
          child: IconButton(
            key: ValueKey('segment_volume_mute_$label'),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            tooltip: muteTooltip,
            iconSize: 18,
            color: iconColor,
            icon: Icon(
              muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
            ),
            onPressed: onToggleMute,
          ),
        ),
      ],
    );
  }
}
