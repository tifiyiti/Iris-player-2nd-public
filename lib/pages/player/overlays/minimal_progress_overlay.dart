import 'package:flutter/material.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/background_playback/services/bg_vm_visibility.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/features/virtual_media/interaction/ui/vm_dual_time.dart';
import 'package:iris/features/virtual_media/store/vm_playback_store.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/control_bar/control_bar_slider.dart';
import 'package:iris/pages/player/control_bar/title_area.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:iris/utils/format_duration_to_minutes.dart';
import 'package:provider/provider.dart';

class MinimalProgressOverlay extends StatelessWidget {
  const MinimalProgressOverlay({
    super.key,
    required this.title,
    this.bgTitleSuffix,
    this.bgTitleNoMedia = false,
    required this.file,
  });

  final String title;

  /// 副音 on-marker appended to the title (see [TitleArea]).
  final String? bgTitleSuffix;

  /// 副音 is on but no media is loaded — the marker renders muted (gray).
  final bool bgTitleNoMedia;
  final FileItem? file;

  @override
  Widget build(BuildContext context) {
    // Visibility gate first — invisible must not subscribe to MediaPlayer
    // position ticks. Previously the select lived above this gate, causing
    // per-tick rebuilds even when returning SizedBox.shrink().
    final isShowControl =
        usePlayerUiStore().select(context, (state) => state.isShowControl);
    final isShowProgress =
        usePlayerUiStore().select(context, (state) => state.isShowProgress);
    if (!isShowProgress || isShowControl || file?.type != ContentType.video) {
      return const SizedBox.shrink();
    }

    final useClassic =
        useAppStore().select(context, (s) => s.useClassicTitleBar);
    final minimalConfig =
        useAppStore().select(context, (s) => s.minimalTitleConfig);

    // Windows AXTree-crash mitigation (#103808 family): this overlay
    // repaints on every position tick while announcing nothing a screen
    // reader needs — exclude it so the engine's accessibility bridge never
    // serializes its churn (the control bar keeps full semantics).
    return ExcludeSemantics(
      child: _MinimalProgressContent(
        title: title,
        bgTitleSuffix: bgTitleSuffix,
        bgTitleNoMedia: bgTitleNoMedia,
        file: file,
        useClassic: useClassic,
        minimalConfig: minimalConfig,
      ),
    );
  }
}

class _MinimalProgressContent extends StatelessWidget {
  const _MinimalProgressContent({
    required this.title,
    required this.bgTitleSuffix,
    required this.bgTitleNoMedia,
    required this.file,
    required this.useClassic,
    required this.minimalConfig,
  });

  final String title;
  final String? bgTitleSuffix;
  final bool bgTitleNoMedia;
  final FileItem? file;
  final bool useClassic;
  final dynamic minimalConfig;

  @override
  Widget build(BuildContext context) {
    final progress =
        context.select<MediaPlayer, ({Duration position, Duration duration})>(
      (player) => (position: player.position, duration: player.duration),
    );

    // B-scheme dual time, compact single-line form (space is tight here):
    // `totalPos / totalDur  subPos/subDur`. VM-only; the bg-suppression gate
    // matches the shared ControlBarSlider so 副音 never shows VM sub times.
    final vmItemRaw = useVmPlaybackStore().select(context, (s) => s.item);
    final bgIsControl = useBackgroundPlaybackStore()
        .select(context, (s) => s.bgOwnsControls);
    final vmSync = useAppStore().select(context, (s) => s.vmDualTimeSync);
    final vmDual = VmDualTime.resolve(
      vmItemForControlTarget(vmItemRaw, bgIsControl: bgIsControl),
      progress.position.inMilliseconds,
      sync: vmSync,
    );
    final bool showVmSub =
        vmDual.showSub && vmDual.segDurMs != null;

    const overlayTextStyle = TextStyle(
      color: Colors.white,
      decoration: TextDecoration.none,
      shadows: [
        Shadow(
          color: Colors.black,
          offset: Offset(0, 0),
          blurRadius: 1,
        ),
      ],
    );

    return Stack(
      children: [
        useClassic
            ? Positioned(
                left: 12,
                top: 12,
                child: Text(
                  title,
                  style: overlayTextStyle.copyWith(fontSize: 20, height: 1),
                ))
              : TitleArea(
                // no Positioned
                title: title,
                bgTitleSuffix: bgTitleSuffix,
                bgTitleNoMedia: bgTitleNoMedia,
                color: Colors.white,
                overlayColor: WidgetStateProperty.resolveWith<Color?>(
                  (states) => Colors.white.withValues(
                      alpha: states.contains(WidgetState.pressed) ? 0.2 : 0.1),
                ),
                saveProgress: context.read<MediaPlayer>().saveProgress,
                config: minimalConfig,
              ),
        const Positioned(
          left: -28,
          right: -28,
          bottom: -16,
          height: 32,
          child: ControlBarSlider(
            disabled: true,
          ),
        ),
        Positioned(
          left: 12,
          bottom: 6,
          child: Text.rich(
            TextSpan(
              text:
                  '${formatDurationToMinutes(Duration(milliseconds: vmDual.displayVirtualMs))} / ${formatDurationToMinutes(progress.duration)}',
              style: overlayTextStyle.copyWith(fontSize: 16, height: 2),
              children: [
                if (showVmSub)
                  TextSpan(
                    text:
                        '  ${formatDurationToMinutes(Duration(milliseconds: vmDual.displayLocalMs))}/${formatDurationToMinutes(Duration(milliseconds: vmDual.segDurMs!))}',
                    style: overlayTextStyle.copyWith(
                      fontSize: 11,
                      height: 2,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
