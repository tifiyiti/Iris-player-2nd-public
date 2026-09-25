import 'package:flutter/material.dart';
import 'package:iris/features/speed/model/speed_rate_scale_math.dart';
import 'package:iris/utils/get_localizations.dart';

/// The preset speeds every mainstream player offers: quarters of a step from
/// 0.25 up to 2.0, plus the 3.0 that heavy skimmers reach for.
///
/// These deliberately sit OFF the 0.1 grid the wheels and the legacy list
/// share — that is the point of a preset row, it reaches values the 0.1 dial
/// cannot address. Values off that grid are safe: the speed gestures resolve
/// through `closestSpeedMatch`, and the only other `speedStops.indexOf` of a
/// raw rate feeds a haptic comparison.
///
/// Nine entries on purpose: the row lays out as a clean 3x3 grid.
const List<double> kRatePresetStops = <double>[
  0.25, 0.5, 0.75, //
  1.0, 1.25, 1.5,
  1.75, 2.0, 3.0,
];

/// Columns in the preset grid.
const int kRatePresetColumns = 3;

/// Fixed height of the label box inside one preset chip.
///
/// Without it a scaled-down label shrinks its own chip: `FittedBox` scales
/// uniformly, so the chip holding the longer "0.25X" would come out SHORTER
/// than the one holding "3.0X" and the grid would stop reading as a grid.
/// Pinning the label height keeps every cell identical while the font inside
/// absorbs the difference.
const double kRateChipLabelHeight = 20.0;

/// One-tap preset grid shared by every picker that offers presets.
///
/// Fixed 3 columns rather than a wrapping row: `Wrap` re-flows to 4+3+2 on a
/// 360px phone, which loses the grid AND leaves the row edges ragged.
class RatePresetChips extends StatelessWidget {
  const RatePresetChips({
    super.key,
    required this.value,
    required this.onSelected,
  });

  /// Currently applied rate; the matching chip is highlighted.
  final double value;

  final ValueChanged<double> onSelected;

  @override
  Widget build(BuildContext context) {
    final List<List<double>> rows = <List<double>>[
      for (int i = 0; i < kRatePresetStops.length; i += kRatePresetColumns)
        kRatePresetStops.sublist(
          i,
          (i + kRatePresetColumns).clamp(0, kRatePresetStops.length),
        ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int r = 0; r < rows.length; r++) ...<Widget>[
          if (r > 0) const SizedBox(height: 6),
          Row(
            children: <Widget>[
              for (int c = 0; c < kRatePresetColumns; c++) ...<Widget>[
                if (c > 0) const SizedBox(width: 8),
                Expanded(
                  child: c < rows[r].length
                      ? _PresetChip(
                          stop: rows[r][c],
                          selected: rows[r][c] == value,
                          onSelected: onSelected,
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.stop,
    required this.selected,
    required this.onSelected,
  });

  final double stop;
  final bool selected;
  final ValueChanged<double> onSelected;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final String label =
        getLocalizations(context).rate_value(formatSpeedLabel(stop));
    // Deliberately NOT a `ChoiceChip`. `RawChip` wraps its content in
    // `Center(widthFactor: 1.0, heightFactor: 1.0)` (see chip.dart), which lays
    // the chip out at its LABEL's natural width and only centres it in the
    // slot — so "0.25X" came out visibly longer than "1.0X" while the slots
    // measured identical. Here the `Material` is the outermost box: under the
    // tight width `Expanded` hands out it must fill the cell, so every preset
    // is the same rectangle whatever its label measures.
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        key: ValueKey<String>('rate_preset_pill_${formatSpeedLabel(stop)}'),
        color: selected ? colors.primaryContainer : colors.surfaceContainerHigh,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? colors.primary : colors.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onSelected(stop),
          child: Padding(
            // Fixed vertical padding around a fixed label box: the pill height
            // is a constant, never derived from how long the label is.
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: SizedBox(
              height: kRateChipLabelHeight,
              child: Center(
                // `scaleDown` shrinks a label that outgrows the cell (long
                // label at a large system font scale) instead of clipping or
                // wrapping it — the font gives, the cell does not.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      color:
                          selected ? colors.onPrimaryContainer : colors.onSurface,
                      // No bold-when-selected: a heavier weight widens the
                      // label, and a label that changes size is one more thing
                      // that can make one cell look unlike its neighbours.
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
