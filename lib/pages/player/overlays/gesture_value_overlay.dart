import 'package:flutter/material.dart';

class GestureValueOverlay extends StatelessWidget {
  const GestureValueOverlay({
    super.key,
    required this.value,
    required this.icon,
    this.valueFormatter,
  });

  /// Normalized value in range [0.0, 1.0]
  final double value;

  /// Icon representing the value semantics (brightness / volume / etc.)
  final IconData icon;

  /// Optional formatter for displaying the value (e.g. "45%", "0.7×")
  final String Function(double)? valueFormatter;

  @override
  Widget build(BuildContext context) {
    final text = valueFormatter?.call(value);

    return Positioned.fill(
      child: Center(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 18, 12),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 24),
              const SizedBox(width: 12),
              SizedBox(
                width: 100,
                child: LinearProgressIndicator(
                  value: value,
                  borderRadius: BorderRadius.circular(4),
                  backgroundColor: Colors.grey,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              if (text != null) ...[
                const SizedBox(width: 12),
                Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
