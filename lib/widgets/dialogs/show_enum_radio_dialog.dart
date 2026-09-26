import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/utils/get_localizations.dart';

Future<void> showEnumRadioDialog<T>({
  required BuildContext context,
  required String title,
  required List<T> values,
  required T currentValue,
  required String Function(T) labelOf,
  required void Function(T) onSelected,
  String? subtitle,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => EnumRadioDialog<T>(
      title: title,
      subtitle: subtitle,
      values: values,
      currentValue: currentValue,
      labelOf: labelOf,
      onSelected: onSelected,
    ),
  );
}

class EnumRadioDialog<T> extends HookWidget {
  const EnumRadioDialog({
    super.key,
    required this.title,
    required this.values,
    required this.currentValue,
    required this.labelOf,
    required this.onSelected,
    this.subtitle,
  });

  final String title;

  /// Optional line under the title. For a dialog whose value is stored per
  /// screen shape, this is what says WHICH shape the radios are about —
  /// without it, changing the value on a phone looks like it did nothing,
  /// because the desktop is still on the old one.
  final String? subtitle;

  final List<T> values;
  final T currentValue;
  final String Function(T value) labelOf;
  final void Function(T value) onSelected;

  @override
  Widget build(BuildContext context) {
    void select(T value) {
      onSelected(value);
      Navigator.pop(context);
    }

    return AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (subtitle != null) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 4),
            ],
            RadioGroup<T>(
              groupValue: currentValue,
              onChanged: (v) {
                if (v != null) select(v);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: values.map((e) {
                  return ListTile(
                    title: Text(labelOf(e)),
                    leading: Radio<T>(value: e),
                    onTap: () => select(e),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(getLocalizations(context).cancel),
        ),
      ],
    );
  }
}
