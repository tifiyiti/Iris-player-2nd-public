import 'package:flutter/material.dart';

/// A plain gray occurrence badge like `(2)` / `(3)` shown on duplicated
/// queue items (the 1-based occurrence of the same media in the queue).
class DuplicateBadge extends StatelessWidget {
  /// 0-based occurrence index of the item.
  final int occurrenceIndex;

  const DuplicateBadge({super.key, required this.occurrenceIndex});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '(${occurrenceIndex + 1})',
        style: TextStyle(
          fontSize: 12,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
