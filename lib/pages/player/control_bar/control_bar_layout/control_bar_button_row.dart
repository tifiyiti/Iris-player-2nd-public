import 'package:flutter/material.dart';

/// Flat, overflow-proof button row.
///
/// Wraps to additional runs instead of clipping, so no button can ever leave
/// the picture. This is the PHONE bar's two-row arrangement: every button is
/// one peer, distributed with the portrait alignment policy.
///
/// Desktop bars must NOT use it to render a left/right pair —
/// [WrapAlignment.spaceBetween] distributes the slack between EVERY adjacent
/// peer, which pulls both groups toward the middle and destroys the
/// transport-group / secondary-group split. Use [ControlBarGroupedRow] there.
class ControlBarButtonRow extends StatelessWidget {
  const ControlBarButtonRow({
    super.key,
    required this.children,
    this.alignment = WrapAlignment.spaceBetween,
    this.spacing = 0,
    this.runSpacing = 0,
  });

  final List<Widget> children;

  /// Alignment of each run inside the filled width.
  final WrapAlignment alignment;

  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: alignment,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: spacing,
        runSpacing: runSpacing,
        children: children,
      ),
    );
  }
}

/// Left/right grouped button row for the desktop linear bars.
///
/// The classic desktop bar packs the transport group flush-left and the
/// secondary group flush-right, leaving ONE large gap between them. The two
/// groups must therefore lay out as two units: a flat `Wrap(spaceBetween)` over
/// every button would spread all of them evenly and lose that split.
///
/// Given two units, [WrapAlignment.spaceBetween] pins [leading] to the left
/// edge and [trailing] to the right edge. When the bar is too narrow for both,
/// the trailing unit simply wraps to a new run, so the row still never clips.
class ControlBarGroupedRow extends StatelessWidget {
  const ControlBarGroupedRow({
    super.key,
    required this.leading,
    required this.trailing,
    this.runSpacing = 0,
  });

  /// Transport group, packed together at the left edge.
  final List<Widget> leading;

  /// Secondary group, packed together at the right edge.
  final List<Widget> trailing;

  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: runSpacing,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: leading),
          Row(mainAxisSize: MainAxisSize.min, children: trailing),
        ],
      ),
    );
  }
}

/// Maps a `MainAxisAlignment` (the phone bar's portrait policy) onto the
/// equivalent `WrapAlignment` used by [ControlBarButtonRow].
WrapAlignment wrapAlignmentFrom(MainAxisAlignment align) => switch (align) {
      MainAxisAlignment.start => WrapAlignment.start,
      MainAxisAlignment.end => WrapAlignment.end,
      MainAxisAlignment.center => WrapAlignment.center,
      MainAxisAlignment.spaceBetween => WrapAlignment.spaceBetween,
      MainAxisAlignment.spaceAround => WrapAlignment.spaceAround,
      MainAxisAlignment.spaceEvenly => WrapAlignment.spaceEvenly,
    };
