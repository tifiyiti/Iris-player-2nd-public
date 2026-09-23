import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

class NormalizedSliderControl extends HookWidget {
  const NormalizedSliderControl({
    super.key,
    required this.showControl,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onChangeEnd,
    this.showValueText = true,
    this.valueBuilder,
    this.icon,
    this.color,
    this.overlayColor,
    this.divisions,
  });

  final VoidCallback showControl;
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  /// Fired once when the drag settles. Callers persist here while [onChanged]
  /// only mutates memory, so a drag never hammers the DB per frame.
  final ValueChanged<double>? onChangeEnd;
  final bool showValueText;
  final Color? color;
  final WidgetStateProperty<Color?>? overlayColor;

  /// Icon shown on the left
  final IconData? icon;

  /// Lets parent control how the value is rendered
  final Widget Function(double value)? valueBuilder;
  final int? divisions;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (PointerSignalEvent event) {
        if (event is PointerScrollEvent) {
          showControl();
          final delta = event.scrollDelta.dy < 0 ? 1 : -1;
          final double next = (value + delta).clamp(min, max);
          onChanged(next);
          // Wheel notches are discrete: commit each one.
          onChangeEnd?.call(next);
        }
      },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          textBaseline: TextBaseline.ideographic,
          children: [
            IconButton(
              tooltip: label,
              icon: Icon(icon ?? Icons.tune_rounded, size: 18, color: color),
              onPressed: () {
                showControl();
                final double mid = (min + max) / 2;
                onChanged(mid); // reset to middle
                onChangeEnd?.call(mid);
              },
              style: ButtonStyle(overlayColor: overlayColor),
            ),
            // Always-visible meaning: tooltips are unreachable on touch.
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                thumbColor: color,
                activeTrackColor: color?.withAlpha(222),
                inactiveTrackColor: color?.withAlpha(99),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 4),
                trackHeight: 2.4,
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                divisions: divisions,
                label: valueBuilder == null ? value.toStringAsFixed(0) : null,
                onChanged: (v) {
                  showControl();
                  onChanged(v);
                },
                onChangeEnd: onChangeEnd,
              ),
            ),
          ),
          if (showValueText) const SizedBox(width: 8),
          if (showValueText)
            (valueBuilder != null ? valueBuilder!(value) : Text(value.toInt().toString())),
        ],
      ),
    );
  }
}
