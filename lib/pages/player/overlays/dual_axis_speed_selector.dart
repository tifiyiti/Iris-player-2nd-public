import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/features/speed/model/speed_gesture_math.dart';
import 'package:iris/globals.dart' show speedStops;
import 'package:iris/utils/get_localizations.dart';

class DualAxisSpeedSelector extends HookWidget {
  const DualAxisSpeedSelector({
    super.key,
    required this.selectedSpeed,
    required this.visualOffset,
    required this.initialSpeed,
    required this.visualOffsetY,
  });

  final double selectedSpeed;
  final double visualOffset;
  final double initialSpeed;
  final double visualOffsetY;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final screenSize = MediaQuery.sizeOf(context);
    final centerX = screenSize.width / 2;
    final centerY = screenSize.height / 2;

    final selectedIndex = speedStops.indexOf(selectedSpeed);
    final initialIndex = speedStops.indexOf(initialSpeed);
    final double hSteps = visualOffset / 64;
    final double vSteps = -visualOffsetY / kSpeedCoarseSensitivity;
    final idx = selectedIndex == -1 ? speedStops.indexOf(1.0) : selectedIndex;
    final wheels = speedCoarseFine(idx);
    final bool atTop = wheels.coarse >= 10;
    final bool coarseZero = wheels.coarse == 0;
    final Axis? activeAxis =
        resolveSpeedLockedAxis(Offset(visualOffset, visualOffsetY));

    return IgnorePointer(
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(color: Colors.black.withValues(alpha: 0.18)),
          ),
          Positioned(
            left: centerX - 170,
            right: centerX - 170 > 0 ? null : 12,
            top: centerY - 150,
            child: Container(
              width: 340,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white12),
                boxShadow: const [
                  BoxShadow(color: Colors.black45, blurRadius: 18, spreadRadius: 2),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.speed_rounded, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text(t.speed_title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${selectedSpeed.toStringAsFixed(1)}×',
                          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _WheelRow(
                    label: 'V',
                    hint: t.speed_hint_v,
                    offset: vSteps,
                    values: _coarseWindow(wheels.coarse),
                    centerPos: 2,
                    grayed: false,
                    hideValue: -1,
                    active: activeAxis != Axis.horizontal,
                  ),
                  const SizedBox(height: 8),
                  _WheelRow(
                    label: 'H',
                    hint: t.speed_hint_h,
                    offset: hSteps,
                    values: _fineWindow(wheels.fine),
                    centerPos: 2,
                    grayed: atTop,
                    hideValue: coarseZero ? 0 : -1,
                    active: activeAxis != Axis.vertical,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _HintChip(
                          icon: Icons.swap_horiz_rounded,
                          text: t.speed_chip_h,
                          active: activeAxis != Axis.vertical),
                      const SizedBox(width: 8),
                      _HintChip(
                          icon: Icons.swap_vert_rounded,
                          text: t.speed_chip_v,
                          active: activeAxis != Axis.horizontal),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t.speed_footer_hint,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: centerX - 1.5,
            top: centerY - 90,
            child: Container(
              width: 3,
              height: 180,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Positioned(
            left: centerX - 90,
            top: centerY - 1.5,
            child: Container(
              width: 180,
              height: 3,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (selectedIndex != -1 && initialIndex != -1)
            Positioned(
              left: 0,
              right: 0,
              top: 56,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Text(
                      '${initialSpeed.toStringAsFixed(1)} → ${selectedSpeed.toStringAsFixed(1)}  (${_deltaLabel(initialSpeed, selectedSpeed)})',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

List<int?> _coarseWindow(int coarse) {
  int c(int v) => v < 0 || v > 10 ? -1 : v;
  return <int?>[c(coarse - 2), c(coarse - 1), coarse, c(coarse + 1), c(coarse + 2)];
}

List<int?> _fineWindow(int fine) {
  return List<int?>.generate(5, (i) => (fine + i - 2) % 10);
}

String _deltaLabel(double a, double b) {
  final d = b - a;
  final sign = d >= 0 ? '+' : '';
  return '$sign${d.toStringAsFixed(1)}';
}

class _WheelRow extends StatelessWidget {
  const _WheelRow({
    required this.label,
    required this.hint,
    required this.offset,
    required this.values,
    required this.centerPos,
    required this.grayed,
    required this.hideValue,
    required this.active,
  });

  final String label;
  final String hint;
  final double offset;
  final List<int?> values;
  final int centerPos;
  final bool grayed;
  final int hideValue;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final double frac = offset - offset.truncate();
    const double cellWidth = 24.0;
    final double pxShift = active ? -frac * cellWidth : 0.0;
    final bool dimmed = grayed || !active;

    return Opacity(
      opacity: active ? 1.0 : 0.55,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: dimmed
              ? Colors.white.withValues(alpha: 0.03)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: Colors.white.withValues(alpha: dimmed ? 0.08 : 0.28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: dimmed ? Colors.white24 : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(label,
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: dimmed ? Colors.white54 : Colors.black)),
                ),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(hint,
                        style: TextStyle(
                            color: Colors.white
                                .withValues(alpha: dimmed ? 0.4 : 0.9),
                            fontSize: 12,
                            fontWeight: FontWeight.w600))),
              ],
            ),
            const SizedBox(height: 6),
            Center(
              child: SizedBox(
                height: 44,
                width: 120,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      height: 30,
                      decoration: BoxDecoration(
                        color: dimmed
                            ? Colors.white.withValues(alpha: 0.04)
                            : Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    Transform.translate(
                      offset: Offset(pxShift, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (int i = 0; i < values.length; i++)
                            _WheelCell(
                              value: values[i],
                              selected: i == centerPos && !dimmed,
                              grayed: dimmed,
                              hidden: values[i] != null &&
                                  (values[i] == -1 || values[i] == hideValue),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WheelCell extends HookWidget {
  const _WheelCell(
      {required this.value,
      required this.selected,
      required this.grayed,
      required this.hidden});

  final int? value;
  final bool selected;
  final bool grayed;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final controller = useAnimationController(
      duration: const Duration(milliseconds: 140),
    );
    useEffect(() {
      if (selected && !grayed && !hidden) controller.forward(from: 0.0);
      return null;
    }, [value, selected, grayed, hidden]);
    final scale = useAnimation(
      CurvedAnimation(parent: controller, curve: Curves.easeOutBack),
    );
    if (hidden || value == null) {
      return const SizedBox(width: 24);
    }
    final Color color = grayed
        ? Colors.white24
        : selected
            ? Colors.white
            : Colors.white54;
    final double pulse = selected && !grayed ? 1.0 + scale * 0.35 : 1.0;
    return SizedBox(
      width: 24,
      child: Center(
        child: Transform.scale(
          scale: pulse,
          child: Text(
            '$value',
            style: TextStyle(
              fontSize: selected ? 20 : 14,
              fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
              color: color,
              height: 1.0,
            ),
          ),
        ),
      ),
    );
  }
}

class _HintChip extends StatelessWidget {
  const _HintChip(
      {required this.icon, required this.text, required this.active});
  final IconData icon;
  final String text;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: active ? 1.0 : 0.45,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: active ? Colors.white70 : Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 4),
            Text(text,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
