import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/speed/model/speed_rate_wheel_math.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';

/// Alarm-clock-style dual-wheel playback-speed picker.
///
/// Two `ListWheelScrollView` wheels: the whole-number wheel (0..10) and the
/// tenths wheel whose DOMAIN follows the whole-number wheel — coarse 0 offers
/// [1..9] (no 0.0), coarse 10 offers [0] only (no 10.1+), otherwise [0..9]
/// (see speed_rate_wheel_math.dart). Opened only while the metadata picker
/// resolves to `dualWheel` (see showRatePickerDialog).
Future<void> showRateWheelDialog(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const RateWheelDialog(),
    );

class RateWheelDialog extends HookWidget {
  const RateWheelDialog({super.key});

  /// Compact fixed heights: the wheels stay usable on small phone screens and
  /// the whole content scrolls if the dialog is height-constrained (landscape).
  static const double _wheelHeight = 120.0;
  static const double _itemExtent = 32.0;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final double rate = useAppStore().select(context, (s) => s.rate);
    final ({int coarse, int fine}) initial = splitRate(rate);
    final coarseState = useState<int>(initial.coarse);
    final fineState = useState<int>(initial.fine);
    final coarseCtrl = useFixedExtentScrollController(initialItem: initial.coarse);
    final fineCtrl = useFixedExtentScrollController(
      initialItem: rateFineIndexForValue(initial.coarse, initial.fine),
    );

    double composed() => composeRate(coarseState.value, fineState.value);

    void onCoarseChanged(int raw) {
      final int next = raw.clamp(kRateCoarseMin, kRateCoarseMax);
      if (next == coarseState.value) return;
      final int carried = fineState.value;
      coarseState.value = next;
      // Re-derive the tenths value inside the new domain and re-index the
      // wheel so the visual keeps matching the clamped value.
      final int fineIndex = rateFineIndexForValue(next, carried);
      fineState.value = rateFineValueAt(next, fineIndex);
      fineCtrl.jumpToItem(fineIndex);
    }

    void save() {
      useAppStore().updateRate(composed());
      Navigator.pop(context);
    }

    Widget wheel(String label, ListWheelScrollView view) => Column(
          children: <Widget>[
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            SizedBox(height: _wheelHeight, child: view),
          ],
        );

    final List<int> fineValues = rateFineValues(coarseState.value);

    return AlertDialog(
      title: Text(t.playback_speed),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '${composed().toStringAsFixed(1)}X',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: wheel(
                    t.rate_wheel_int_label,
                    ListWheelScrollView.useDelegate(
                      controller: coarseCtrl,
                      itemExtent: _itemExtent,
                      diameterRatio: 1.4,
                      physics: const FixedExtentScrollPhysics(),
                      onSelectedItemChanged: onCoarseChanged,
                      childDelegate: ListWheelChildBuilderDelegate(
                        childCount: kRateCoarseMax - kRateCoarseMin + 1,
                        builder: (_, int i) =>
                            Center(child: Text('${kRateCoarseMin + i}')),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: wheel(
                    t.rate_wheel_dec_label,
                    ListWheelScrollView.useDelegate(
                      controller: fineCtrl,
                      itemExtent: _itemExtent,
                      diameterRatio: 1.4,
                      physics: const FixedExtentScrollPhysics(),
                      onSelectedItemChanged: (int i) => fineState.value =
                          rateFineValueAt(coarseState.value, i),
                      childDelegate: ListWheelChildBuilderDelegate(
                        childCount: fineValues.length,
                        builder: (_, int i) => Center(
                          child: Text('${rateFineValues(coarseState.value)[i]}'),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              t.rate_wheel_hint,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.cancel),
        ),
        FilledButton(onPressed: save, child: Text(t.save)),
      ],
    );
  }
}
