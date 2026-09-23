import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/pages/player/control_bar/circle_panel_width_slider.dart';
import 'package:iris/pages/player/control_bar/control_bar_widgets/control_bar_constants.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/a11y_tooltip.dart';
import 'package:popover/popover.dart';

Future<void> showCircleSliderLandscapePercentPopover(
  BuildContext context,
  void Function() showControl,
) async =>
    showPopover(
      context: context,
      bodyBuilder: (context) => Container(
        padding: EdgeInsets.fromLTRB(8, 0, 16, 0),
        child: CircleSliderLandscapePercentControl(showControl: showControl),
      ),
      direction: PopoverDirection.top,
      width: 240,
      height: 48,
      arrowHeight: 0,
      arrowWidth: 0,
      backgroundColor: Theme.of(context).colorScheme.surface,
      barrierColor: Colors.transparent,
    );

class CircleSliderLandscapePercentControl extends HookWidget {
  const CircleSliderLandscapePercentControl({
    super.key,
    required this.showControl,
    this.showPercentText = true,
    this.color,
    this.overlayColor,
  });

  final void Function() showControl;
  final bool showPercentText;
  final Color? color;
  final WidgetStateProperty<Color?>? overlayColor;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final clsPercent = useAppStore().select(context, (state) => state.circleLandscapePercent);
    return Listener(
      onPointerSignal: (PointerSignalEvent event) async {
        if (event is PointerScrollEvent) {
          if (event.scrollDelta.dy < 0) {
            showControl();
            useAppStore().updateCircleLandscapePercent(clsPercent + 1);
          } else {
            showControl();
            useAppStore().updateCircleLandscapePercent(clsPercent - 1);
          }
        }
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        textBaseline: TextBaseline.ideographic,
        children: [
          a11yTooltipIconButton(
            context: context,
            tooltip: '${t.circle_slider_landscape_percent} ',
            icon: Icon(
              Icons.space_bar,
              size: kIconSizeSecondary,
              color: color,
            ),
            onPressed: () {
              showControl();
              useAppStore().updateCircleLandscapePercent(40);
            },
            style: ButtonStyle(overlayColor: overlayColor),
          ),
          Expanded(
            child: CircleSliderPanelWidthSlider(
              showControl: showControl,
              color: color,
            ),
          ),
          if (showPercentText) const SizedBox(width: 8),
          if (showPercentText) Text('${clsPercent >= 90 ? '' : '  '}$clsPercent'),
        ],
      ),
    );
  }
}
