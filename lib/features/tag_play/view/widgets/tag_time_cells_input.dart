import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/utils/get_localizations.dart';

/// Six two-digit cells `年/月/日 + 时/分/秒` shared by the tag policy pickers.
typedef TagTimeCells = ({int y, int mo, int d, int h, int mi, int s});

/// Lower bound of every custom tag duration: 5 minutes.
const int kTagTimeMinSeconds = 5 * 60;

/// Upper bound: `99年99月99日 99时99分99秒` (approx, month = 30 days).
const int kTagTimeMaxSeconds = ((99 * 365 + 99 * 30 + 99) * 86400) +
    (99 * 3600 + 99 * 60 + 99);

/// Parses the six cells into a [Duration], clamped to
/// [kTagTimeMinSeconds]..[kTagTimeMaxSeconds].
Duration tagDurationFromCells(TagTimeCells cells) {
  final seconds = cells.y * 365 * 86400 +
      cells.mo * 30 * 86400 +
      cells.d * 86400 +
      cells.h * 3600 +
      cells.mi * 60 +
      cells.s;
  return Duration(
    seconds: seconds.clamp(kTagTimeMinSeconds, kTagTimeMaxSeconds),
  );
}

/// Decomposes a [Duration] into display cells (clamped first).
TagTimeCells tagCellsFromDuration(Duration d) {
  final seconds = d.inSeconds.clamp(kTagTimeMinSeconds, kTagTimeMaxSeconds);
  final days = seconds ~/ 86400;
  final years = days ~/ 365;
  final months = (days % 365) ~/ 30;
  final dayRemainder = days - years * 365 - months * 30;
  return (
    y: years,
    mo: months,
    d: dayRemainder,
    h: (seconds % 86400) ~/ 3600,
    mi: (seconds % 3600) ~/ 60,
    s: seconds % 60,
  );
}

/// Custom per-tag time picker replacing the fixed duration options.
///
/// "永久" (a null duration) is a dedicated toggle; the non-permanent branch
/// renders two rows of two-digit cells (`00年00月00日` / `00时00分00秒`).
/// Typing two digits auto-advances to the next cell; Backspace on an empty
/// cell moves back. Values are clamped to [kTagTimeMinSeconds] lower bound.
class TagTimeCellsInput extends HookWidget {
  const TagTimeCellsInput({
    super.key,
    required this.initial,
    required this.fallback,
    required this.onChanged,
  });

  /// Current value; null means "永久".
  final Duration? initial;

  /// Duration shown when the user switches off "永久" on a tag that had none.
  final Duration fallback;

  /// Emits the edited value; null when "永久" is selected.
  final ValueChanged<Duration?> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final permanent = useState(initial == null);
    final cells = useState<TagTimeCells>(
      tagCellsFromDuration(initial ?? fallback),
    );
    final focusNodes = useMemoized(
      () => List.generate(6, (_) => FocusNode()),
      const [],
    );
    final controllers = useMemoized(
      () => List.generate(6, (_) => TextEditingController()),
      const [],
    );
    // Seed the controllers exactly once (initial build).
    final seeded = useRef(false);
    if (!seeded.value) {
      seeded.value = true;
      final vals = [cells.value.y, cells.value.mo, cells.value.d,
          cells.value.h, cells.value.mi, cells.value.s];
      for (var i = 0; i < 6; i++) {
        controllers[i].text = vals[i].toString().padLeft(2, '0');
      }
    }

    void emit({required bool permanentNow}) {
      onChanged(permanentNow ? null : tagDurationFromCells(cells.value));
    }

    void onCellChanged(int index, String raw) {
      final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
      final limited = digits.length > 2 ? digits.substring(0, 2) : digits;
      cells.value = _withCell(cells.value, index, int.tryParse(limited) ?? 0);
      if (controllers[index].text != limited) {
        controllers[index].text = limited;
      }
      emit(permanentNow: false);
      if (limited.length == 2 && index < 5) {
        focusNodes[index + 1].requestFocus();
      }
    }

    Widget cell(int index, String unit) {
      return Focus(
        onKeyEvent: (node, event) {
          final backspace = event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.backspace;
          if (backspace &&
              index > 0 &&
              controllers[index].text.isEmpty) {
            focusNodes[index - 1].requestFocus();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 52,
              child: TextField(
                controller: controllers[index],
                focusNode: focusNodes[index],
                enabled: !permanent.value,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 2,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(
                  isDense: true,
                  counterText: '',
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
                onChanged: (v) => onCellChanged(index, v),
              ),
            ),
            const SizedBox(width: 2),
            Text(unit, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(width: 8),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(t.tag_cells_permanent),
          subtitle: permanent.value
              ? null
              : Text(
                  _formatPreview(tagDurationFromCells(cells.value)),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
          value: permanent.value,
          onChanged: (v) {
            permanent.value = v;
            emit(permanentNow: v);
          },
        ),
        if (!permanent.value) ...[
          Row(children: [
            cell(0, t.tag_cells_year),
            cell(1, t.tag_cells_month),
            cell(2, t.tag_cells_day),
          ]),
          Row(children: [
            cell(3, t.tag_cells_hour),
            cell(4, t.tag_cells_minute),
            cell(5, t.tag_cells_second),
          ]),
        ],
      ],
    );
  }

  TagTimeCells _withCell(TagTimeCells c, int i, int v) {
    switch (i) {
      case 0:
        return (y: v, mo: c.mo, d: c.d, h: c.h, mi: c.mi, s: c.s);
      case 1:
        return (y: c.y, mo: v, d: c.d, h: c.h, mi: c.mi, s: c.s);
      case 2:
        return (y: c.y, mo: c.mo, d: v, h: c.h, mi: c.mi, s: c.s);
      case 3:
        return (y: c.y, mo: c.mo, d: c.d, h: v, mi: c.mi, s: c.s);
      case 4:
        return (y: c.y, mo: c.mo, d: c.d, h: c.h, mi: v, s: c.s);
      default:
        return (y: c.y, mo: c.mo, d: c.d, h: c.h, mi: c.mi, s: v);
    }
  }

  String _formatPreview(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    final days = d.inDays;
    return days > 0 ? '$days 天 $h:$m:$s' : '$m:$s';
  }
}