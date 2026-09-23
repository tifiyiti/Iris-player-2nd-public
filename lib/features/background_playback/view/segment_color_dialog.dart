import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/features/background_playback/rule/segment_color.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/layout_breakpoints.dart';

/// Adaptive segment-colour picker: a bottom sheet on narrow/phone widths and a
/// centered dialog on desktop/tablet. Returns the chosen opaque ARGB, or null
/// when dismissed.
///
/// The palette is the shared [kSegmentColorPresets]; a hand-tuned RGB editor
/// covers colours outside it. Alpha is locked at FF by
/// [normalizeSegmentColorArgb] — a translucent label bar would vanish against
/// the video and read as "no mapping". The shell is keyboard-free (sliders
/// only) so it needs no inset padding dance.
Future<int?> showSegmentColorDialog(
  BuildContext context, {
  required int initialArgb,
}) {
  final useSheet = isMobileWidthLayout(context);
  final Widget content = _SegmentColorForm(initialArgb: initialArgb);
  if (useSheet) {
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: content,
        ),
      ),
    );
  }
  return showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      content: SizedBox(width: 360, child: content),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(getLocalizations(context).cancel),
        ),
      ],
    ),
  );
}

class _SegmentColorForm extends HookWidget {
  const _SegmentColorForm({required this.initialArgb});

  final int initialArgb;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final theme = Theme.of(context);
    final rgb = useState(normalizeSegmentColorArgb(initialArgb));

    void emit(int argb) => Navigator.of(context).pop(normalizeSegmentColorArgb(argb));

    final color = Color(rgb.value);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: theme.dividerColor),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                t.bg_segment_color_title,
                style: theme.textTheme.titleSmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final preset in kSegmentColorPresets)
              InkWell(
                onTap: () => emit(preset),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Color(preset),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: preset == rgb.value
                          ? theme.colorScheme.primary
                          : theme.dividerColor,
                      width: preset == rgb.value ? 2 : 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _channel(t, 'R', (rgb.value >> 16) & 0xFF,
            (v) => rgb.value = (rgb.value & 0xFF00FFFF) | (v << 16)),
        _channel(t, 'G', (rgb.value >> 8) & 0xFF,
            (v) => rgb.value = (rgb.value & 0xFFFF00FF) | (v << 8)),
        _channel(t, 'B', rgb.value & 0xFF,
            (v) => rgb.value = (rgb.value & 0xFFFFFF00) | v),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(segmentColorLabel(rgb.value),
                style: theme.textTheme.labelMedium),
            const Spacer(),
            TextButton.icon(
              onPressed: () => rgb.value = randomSegmentColorArgb(),
              icon: const Icon(Icons.casino_outlined, size: 18),
              label: Text(t.bg_segment_color_random),
            ),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: () => emit(rgb.value),
              child: Text(t.ok),
            ),
          ],
        ),
      ],
    );
  }

  Widget _channel(
    AppLocalizations t,
    String label,
    int value,
    ValueChanged<int> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(width: 18, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.toDouble().clamp(0, 255),
            max: 255,
            divisions: 255,
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
        SizedBox(width: 32, child: Text('$value')),
      ],
    );
  }
}
