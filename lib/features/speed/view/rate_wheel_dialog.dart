import 'package:flutter/material.dart';
import 'package:iris/features/speed/view/rate_picker_card.dart';
import 'package:iris/features/speed/view/rate_wheels.dart'
    show RateWheels, composeFromRate;

// Re-exported so existing imports of this file keep seeing the wheel metrics
// they already depend on.
export 'package:iris/features/speed/view/rate_wheels.dart'
    show kRateWheelBandInset, kRateWheelDotWidth, kRateWheelHeight,
        kRateWheelItemExtent;

/// Alarm-clock-style dual-wheel playback-speed picker.
///
/// Deliberately text-free: no column labels and no caption explaining the
/// coupling rules. The two wheels plus a decimal point between them read as a
/// single number (`1 . 5`), and the user learns that coarse 0 drops the 0 and
/// coarse 10 only offers 0 simply by spinning a wheel — every pixel instead
/// goes to the digits.
///
/// Opened while the metadata picker resolves to `dualWheel`
/// (see showRatePickerDialog). Rendered in the shared draggable card, so the
/// wheels preview live and Cancel / Save behave like every other shape.
Future<void> showRateWheelDialog(BuildContext context) =>
    showDraggableRateCard(context, const RateWheelDialog());

/// Width the wheel card asks for.
///
/// The wheel needs far less room than the slider: each column only ever holds
/// one or two digits, and at the shared width they stretched into flat, empty
/// lanes (a single digit was sitting in 116px, now 98).
///
/// 260 is the width at which the Cancel / Save row still fits on ONE line for
/// every supported locale — German action labels alone need ~210px of the 220
/// the card then offers. Narrower (220) looked better but made the buttons
/// wrap to two rows.
const double kRateWheelCardMaxWidth = 260.0;

class RateWheelDialog extends StatelessWidget {
  const RateWheelDialog({super.key});

  @override
  Widget build(BuildContext context) => RatePickerCard(
        maxWidth: kRateWheelCardMaxWidth,
        buildContent: (BuildContext context, RatePickerHandles handles) =>
            RateWheels(
          // A preset such as 0.25 is off the 0.1 grid the wheels address; open
          // on the value they will actually commit so the title and the digits
          // never disagree.
          initialRate: composeFromRate(handles.current),
          onChanged: handles.preview,
        ),
      );
}
