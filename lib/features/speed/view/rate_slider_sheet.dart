import 'package:flutter/material.dart';
import 'package:iris/features/speed/model/speed_rate_scale_math.dart';
import 'package:iris/features/speed/view/rate_preset_chips.dart';
import 'package:iris/features/speed/view/rate_picker_card.dart';
import 'package:iris/utils/get_localizations.dart';

/// Media3-style speed picker: one segmented-linear slider over a preset grid,
/// presented in the shared draggable card.
///
/// This is the Google-sanctioned shape (`PlaybackSpeedBottomSheet` in the
/// androidx/media demo), and it uses the horizontal axis the way Apple HIG
/// expects — minimum on the leading edge, value above the track.
Future<void> showRateSliderSheet(BuildContext context) =>
    showDraggableRateCard(context, const RateSliderSheet());

class RateSliderSheet extends StatelessWidget {
  const RateSliderSheet({super.key});

  @override
  Widget build(BuildContext context) =>
      RatePickerCard(buildContent: buildRateSliderBody);
}

/// The slider + tick labels + preset grid.
Widget buildRateSliderBody(BuildContext context, RatePickerHandles handles) =>
    Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Slider(
          value: rateToFraction(handles.current),
          onChanged: (double t) => handles.preview(fractionToRate(t)),
        ),
        const RateScaleLabels(),
        const SizedBox(height: 10),
        RatePresetChips(
          value: handles.current,
          onSelected: handles.preview,
        ),
      ],
    );

/// The four tick labels under the track. Positions come from the segmented
/// mapping itself, so `1.0` and `2.0` sit where the scale actually bends
/// rather than at a linear quarter/third of the way along.
class RateScaleLabels extends StatelessWidget {
  const RateScaleLabels({super.key});

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final TextStyle? style = Theme.of(context).textTheme.labelSmall;
    return SizedBox(
      height: 16,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: rateScaleTicks().map((({double fraction, double rate}) tick) {
          return Align(
            alignment: Alignment(tick.fraction * 2 - 1, 0),
            child: Text(
              t.rate_value(formatSpeedLabel(tick.rate)),
              style: style,
            ),
          );
        }).toList(),
      ),
    );
  }
}
