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
    return ChoiceChip(
      // Every cell is the same rectangle because `Expanded` pins the width and
      // a SINGLE line pins the height — so the LABEL has to give, not the cell.
      // `maxLines`/`softWrap` are what make that true: without them a long
      // label ("0.25X" at a large system font scale) wraps, that one row grows
      // taller, and the grid stops reading as a grid. `scaleDown` then shrinks
      // the single line to fit instead of clipping it.
      label: SizedBox(
        height: kRateChipLabelHeight,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            getLocalizations(context).rate_value(formatSpeedLabel(stop)),
            maxLines: 1,
            softWrap: false,
          ),
        ),
      ),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      selected: selected,
      showCheckmark: false,
      selectedColor: colors.primaryContainer,
      labelStyle: TextStyle(
        color: selected ? colors.onPrimaryContainer : colors.onSurface,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
      ),
      // A 3x3 grid of padded chips costs ~40px per row; the compact density
      // and the wrapped-away tap padding bring that to ~34.
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onSelected: (_) => onSelected(stop),
    );
  }
}
