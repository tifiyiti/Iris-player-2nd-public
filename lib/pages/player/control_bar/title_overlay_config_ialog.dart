import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/models/store/title_overlay_config.dart';
import 'package:iris/utils/get_localizations.dart';

Future<void> showTitleOverlayConfigDialog({
  required BuildContext context,
  required String title,
  required TitleOverlayConfig initial,
  required Future<void> Function(TitleOverlayConfig) onConfirmed,
}) {
  return showDialog(
    context: context,
    builder: (_) => TitleOverlayConfigDialog(
      title: title,
      initial: initial,
      onConfirmed: onConfirmed,
    ),
  );
}

class TitleOverlayConfigDialog extends HookWidget {
  const TitleOverlayConfigDialog({
    super.key,
    required this.title,
    required this.initial,
    required this.onConfirmed,
  });

  final String title;
  final TitleOverlayConfig initial;
  final Future<void> Function(TitleOverlayConfig) onConfirmed;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);

    final config = useState<TitleOverlayConfig>(initial);

    void toggle(TitleField field, bool value) {
      final c = config.value;
      switch (field) {
        case TitleField.appIcon:
          config.value = c.copyWith(showAppIcon: value);
          break;
        case TitleField.battery:
          config.value = c.copyWith(showBattery: value);
          break;
        case TitleField.time:
          config.value = c.copyWith(showTime: value);
          break;
        case TitleField.queueIndex:
          config.value = c.copyWith(showQueueIndex: value);
          break;
        case TitleField.mediaName:
          config.value = c.copyWith(showMediaName: value);
          break;
      }
    }

    return AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          children: [
            ...TitleField.values.map((f) {
              return CheckboxListTile(
                value: switch (f) {
                  TitleField.appIcon => config.value.showAppIcon,
                  TitleField.battery => config.value.showBattery,
                  TitleField.time => config.value.showTime,
                  TitleField.queueIndex => config.value.showQueueIndex,
                  TitleField.mediaName => config.value.showMediaName,
                },
                title: Text(f.label(t)),
                onChanged: (v) => toggle(f, v ?? false),
              );
            }),
            const SizedBox(height: 12),
            Text(t.title_font_size),
            Slider(
              min: 12,
              max: 36,
              divisions: 24,
              value: config.value.fontSize,
              label: config.value.fontSize.toStringAsFixed(0),
              onChanged: (v) => config.value = config.value.copyWith(fontSize: v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.cancel),
        ),
        ElevatedButton(
          onPressed: () {
            final result = config.value;
            Navigator.pop(context);
            onConfirmed(result);
          },
          child: Text(t.save),
        ),
      ],
    );
  }
}
