import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/pages/player/control_bar/control_bar_widgets/control_bar_constants.dart';
import 'package:iris/pages/player/control_bar/volume_control.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/a11y_tooltip.dart';

class AdaptiveVolumeControl extends HookWidget {
  const AdaptiveVolumeControl({
    super.key,
    required this.showControl,
    required this.showControlForHover,
    this.color,
    this.overlayColor,
  });

  final void Function() showControl;
  final Future<void> Function(Future<void>) showControlForHover;
  final Color? color;
  final WidgetStateProperty<Color?>? overlayColor;

  @override
  Widget build(BuildContext context) {
    final volume = useAppStore().select(context, (s) => s.volume);
    final isMuted = useAppStore().select(context, (s) => s.isMuted);
    final t = getLocalizations(context);
    final width = MediaQuery.sizeOf(context).width;

    if (width < kVolumeControlBreakpoints) {
      return a11yTooltipIconButton(
        context: context,
        tooltip: '${t.volume}: $volume',
        icon: Icon(
          isMuted || volume == 0
              ? Icons.volume_off_rounded
              : volume < 50
                  ? Icons.volume_down_rounded
                  : Icons.volume_up_rounded,
          size: kIconSizeSecondary,
          color: color,
        ),
        onPressed: () => showControlForHover(
          showVolumePopover(context, showControl),
        ),
        style: ButtonStyle(overlayColor: overlayColor),
      );
    }

    return SizedBox(
      width: kVolumeSliderWidth,
      child: VolumeControl(
        showControl: showControl,
        showVolumeText: false,
        color: color,
        overlayColor: overlayColor,
      ),
    );
  }
}
