import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/controls/normalized_slider_control.dart';
import 'package:popover/popover.dart';

Future<void> showCircleSliderScaleControlPopover(
  BuildContext context,
  void Function() showControl,
) async =>
    showPopover(
      context: context,
      bodyBuilder: (context) => Container(
        padding: EdgeInsets.fromLTRB(8, 0, 16, 0),
        child: CircleSliderScaleControl(showControl: showControl),
      ),
      direction: PopoverDirection.top,
      width: 240,
      height: 48,
      arrowHeight: 0,
      arrowWidth: 0,
      backgroundColor: Theme.of(context).colorScheme.surface,
      barrierColor: Colors.transparent,
    );

class CircleSliderScaleControl extends HookWidget {
  const CircleSliderScaleControl({
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
    final t = getLocalizations(context);
    final scale = useAppStore().select(context, (state) => state.circleSliderScale);

    return NormalizedSliderControl(
      showControl: showControl,
      icon: Icons.expand,
      label: '${t.circle_slider_scale} ', // or localized
      value: scale * 100, // map 0.0-1.0 → 0-100 for slider
      min: 0,
      max: 100,
      onChanged: (v) => useAppStore().updateCircleSliderScale(v / 100.0),
      valueBuilder: (v) => Text('${v.toInt()}%'),
      color: color,
      overlayColor: overlayColor,
    );
  }
}
