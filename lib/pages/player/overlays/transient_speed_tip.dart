import 'package:flutter/material.dart';

class TransientSpeedTip extends StatelessWidget {
  const TransientSpeedTip({
    super.key,
    required this.speed,
    required this.fading,
    this.showDualHint = false,
  });

  final double speed;
  final bool fading;
  final bool showDualHint;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 30,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedOpacity(
          opacity: fading ? 0.0 : 1.0,
          duration: const Duration(seconds: 7),
          curve: Curves.linear,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${speed.toStringAsFixed(1)}×',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
