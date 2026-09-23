import 'package:flutter/material.dart';
import 'package:iris/utils/get_localizations.dart';

/// PotPlayer-style drag-and-drop split indicator.
///
/// Painted full-screen while a filesystem drag hovers the player: the top
/// [appendPercent] strip announces "add to play queue"; the remainder
/// announces "play" (override). Purely decorative — it never intercepts the
/// pointer, so the drop still reaches the player's [DropTarget].
class DropZoneOverlay extends StatelessWidget {
  const DropZoneOverlay({super.key, required this.appendPercent});

  /// Top share of the height (0–100) that appends instead of overriding.
  final double appendPercent;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight;
          final split =
              height * (appendPercent.clamp(0.0, 100.0) / 100.0);
          return Column(
            children: [
              Container(
                height: split,
                width: double.infinity,
                color: const Color(0xFF808080),
                alignment: Alignment.center,
                child: Text(
                  t.drop_zone_append_label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFF2F2F2),
                    fontWeight: FontWeight.w700,
                    fontSize: 40,
                  ),
                ),
              ),
              Container(height: 1, color: const Color(0xFFFFFFFF)),
              Expanded(
                child: Container(
                  width: double.infinity,
                  color: const Color(0xFFFFFFFF),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.play_arrow_rounded,
                        size: 96,
                        color: Color(0xFFBDBDBD),
                      ),
                      Text(
                        t.drop_zone_play_label,
                        style: const TextStyle(
                          color: Color(0xFFBDBDBD),
                          fontWeight: FontWeight.w700,
                          fontSize: 40,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
