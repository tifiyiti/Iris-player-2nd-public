import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/features/speed/model/speed_rate_wheel_math.dart';

/// One wheel entry's height, doubled as the selection-band height.
///
/// Public so tests can derive a drag that spans exactly one snap.
const double kRateWheelItemExtent = 38.0;

/// Wheel viewport height: four entries (one selected plus neighbours above and
/// below) — compact enough for a small portrait phone, still a real dial.
const double kRateWheelHeight = kRateWheelItemExtent * 4;

/// Width of the gap between the two wheels that hosts the decimal point.
const double kRateWheelDotWidth = 24.0;

/// Horizontal inset of the selection band.
///
/// The band used to run edge to edge and read as a heavy bar that made the
/// whole dial look coarse; insetting it is what the iOS wheel does.
const double kRateWheelBandInset = 12.0;

/// The on-grid rate the wheels present for [rate].
///
/// A preset such as 0.25 is off the 0.1 grid the wheels address, so opening a
/// picker over it must show the value it will actually commit (0.3) rather
/// than the raw one — otherwise the title and the digits disagree until the
/// user first touches a wheel.
double composeFromRate(double rate) {
  final ({int coarse, int fine}) parts = splitRate(rate);
  return composeRate(parts.coarse, parts.fine);
}

/// The coupled coarse/tenths pair as ONE widget, shared by every picker that
/// offers a wheel.
///
/// The coupling rules themselves live in `speed_rate_wheel_math.dart`; this
/// widget only owns the scroll controllers and the re-index step that keeps
/// the tenths wheel inside the new domain after the coarse wheel moves. It
/// reports the composed rate through [onChanged] on every committed wheel
/// step and never touches the store, so the caller decides whether a step is
/// a live preview or something to save explicitly.
class RateWheels extends HookWidget {
  const RateWheels({
    super.key,
    required this.initialRate,
    required this.onChanged,
  });

  final double initialRate;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final ({int coarse, int fine}) initial = splitRate(initialRate);
    final coarseState = useState<int>(initial.coarse);
    final fineState = useState<int>(initial.fine);
    final coarseCtrl =
        useFixedExtentScrollController(initialItem: initial.coarse);
    final fineCtrl = useFixedExtentScrollController(
      initialItem: rateFineIndexForValue(initial.coarse, initial.fine),
    );

    double composed() => composeRate(coarseState.value, fineState.value);

    void onCoarseChanged(int raw) {
      final int next = raw.clamp(kRateCoarseMin, kRateCoarseMax);
      if (next == coarseState.value) return;
      HapticFeedback.selectionClick();
      final int carried = fineState.value;
      coarseState.value = next;
      // Re-derive the tenths value inside the new domain and re-index the
      // wheel so the visual keeps matching the clamped value.
      final int fineIndex = rateFineIndexForValue(next, carried);
      fineState.value = rateFineValueAt(next, fineIndex);
      fineCtrl.jumpToItem(fineIndex);
      onChanged(composed());
    }

    final List<int> fineValues = rateFineValues(coarseState.value);
    // One uniform weight, deliberately NOT bolding the selected row: iOS does
    // not either, and tracking the selection just to re-style it would rebuild
    // both wheels on every step. The magnification and the neighbour fade are
    // what make the centre row read as chosen.
    const TextStyle digitStyle =
        TextStyle(fontSize: 24, fontWeight: FontWeight.w500);

    Widget wheel({
      required FixedExtentScrollController controller,
      required int childCount,
      required ValueChanged<int> onSelectedItemChanged,
      required String Function(int index) labelOf,
    }) =>
        ListWheelScrollView.useDelegate(
          controller: controller,
          itemExtent: kRateWheelItemExtent,
          diameterRatio: 1.9,
          useMagnifier: true,
          magnification: 1.10,
          overAndUnderCenterOpacity: 0.26,
          physics: const FixedExtentScrollPhysics(),
          onSelectedItemChanged: onSelectedItemChanged,
          childDelegate: ListWheelChildBuilderDelegate(
            childCount: childCount,
            builder: (_, int i) =>
                Center(child: Text(labelOf(i), style: digitStyle)),
          ),
        );

    return SizedBox(
      height: kRateWheelHeight,
      child: Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          // Inset, barely-tinted band with hairline edges: the selected row
          // still spans BOTH wheels and the decimal point, so `1 . 5` keeps
          // reading as one number, but without the slab of grey.
          Positioned(
            key: const ValueKey('rate_wheel_band'),
            left: kRateWheelBandInset,
            right: kRateWheelBandInset,
            top: (kRateWheelHeight - kRateWheelItemExtent) / 2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.onSurface.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.symmetric(
                  horizontal: BorderSide(
                    color: colors.outlineVariant.withValues(alpha: 0.7),
                  ),
                ),
              ),
              child: const SizedBox(height: kRateWheelItemExtent),
            ),
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: wheel(
                  controller: coarseCtrl,
                  childCount: kRateCoarseMax - kRateCoarseMin + 1,
                  onSelectedItemChanged: onCoarseChanged,
                  labelOf: (int i) => '${kRateCoarseMin + i}',
                ),
              ),
              SizedBox(
                width: kRateWheelDotWidth,
                child: Center(
                  child: Text(
                    '.',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w500,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: wheel(
                  controller: fineCtrl,
                  childCount: fineValues.length,
                  onSelectedItemChanged: (int i) {
                    HapticFeedback.selectionClick();
                    final int value = rateFineValueAt(coarseState.value, i);
                    fineState.value = value;
                    onChanged(composeRate(coarseState.value, value));
                  },
                  labelOf: (int i) => '${fineValues[i]}',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
