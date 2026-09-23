import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/controls/normalized_slider_control.dart';
import 'package:popover/popover.dart';

Future<void> showCircleSliderLandscapePercentControlPopover(
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
    this.color,
    this.overlayColor,
  });

  final VoidCallback showControl;
  final Color? color;
  final WidgetStateProperty<Color?>? overlayColor;

  @override
  Widget build(BuildContext context) {
    final clsPercent = useAppStore().select(context, (state) => state.circleLandscapePercent);

    return NormalizedSliderControl(
      showControl: showControl,
      icon: Icons.space_bar_rounded,
      label: getLocalizations(context).circle_slider_landscape_percent,
      value: clsPercent.toDouble(),
      min: 30,
      max: 90,
      onChanged: (v) => useAppStore().updateCircleLandscapePercent(v.toInt()),
      color: color,
      overlayColor: overlayColor,
      valueBuilder: (v) => Text('${v.toInt()}%'),
    );
  }
}
