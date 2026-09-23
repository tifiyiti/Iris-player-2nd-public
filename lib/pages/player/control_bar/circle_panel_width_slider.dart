import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/store/use_app_store.dart';

class CircleSliderPanelWidthSlider extends HookWidget {
  const CircleSliderPanelWidthSlider({
    super.key,
    required this.showControl,
    this.color,
  });

  final void Function() showControl;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final clsPercent = useAppStore().select(context, (state) => state.circleLandscapePercent);

    return ExcludeFocus(
      child: SizedBox(
        width: 128,
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            thumbColor: color,
            activeTrackColor: color?.withAlpha(222),
            inactiveTrackColor: color?.withAlpha(99),
            thumbShape: RoundSliderThumbShape(
              enabledThumbRadius: 5.6,
            ),
            overlayShape: const RoundSliderOverlayShape(
              overlayRadius: 4,
            ),
            trackHeight: 2.4,
          ),
          child: Slider(
            value: clsPercent.toDouble(),
            onChanged: (value) {
              showControl();
              useAppStore().updateCircleLandscapePercent((value).toInt());
            },
            min: 30,
            max: 90,
          ),
        ),
      ),
    );
  }
}
