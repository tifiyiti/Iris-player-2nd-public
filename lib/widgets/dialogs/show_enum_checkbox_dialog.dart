import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/utils/get_localizations.dart';

Future<void> showEnumCheckboxDialog<T>({
  required BuildContext context,
  required String title,
  required List<T> values,
  Set<T>? initialSelected,
  required String Function(T) labelOf,
  required Future<void> Function(Set<T> selected) onConfirmed,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => EnumCheckboxDialog<T>(
      title: title,
      values: values,
      initialSelected: initialSelected ?? const {},
      labelOf: labelOf,
      onConfirmed: onConfirmed,
    ),
  );
}

class EnumCheckboxDialog<T> extends HookWidget {
  const EnumCheckboxDialog({
    super.key,
    required this.title,
    required this.values,
    required this.initialSelected,
    required this.labelOf,
    required this.onConfirmed,
  });

  final String title;
  final List<T> values;
  final Set<T> initialSelected;
  final String Function(T value) labelOf;
  final Future<void> Function(Set<T> selected) onConfirmed;

  @override
  Widget build(BuildContext context) {
    final selected = useState<Set<T>>({...initialSelected});

    void toggle(T value, bool checked) {
      final next = {...selected.value};
      checked ? next.add(value) : next.remove(value);
      selected.value = next;
    }

    void confirm() {
      final result = {...selected.value}; // snapshot
      Navigator.pop(context); // close first
      onConfirmed(result); // async happens outside context
    }

    return AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: values.map((e) {
            return CheckboxListTile(
              value: selected.value.contains(e),
              title: Text(labelOf(e)),
              onChanged: (v) => toggle(e, v ?? false),
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(getLocalizations(context).cancel),
        ),
        ElevatedButton(
          onPressed: selected.value.isEmpty ? null : confirm,
          child: Text(getLocalizations(context).reset),
        ),
      ],
    );
  }
}

Future<void> showGroupedCheckboxDialog({
  required BuildContext context,
  required String title,
  required List<CheckboxGroup> groups,
  required Future<void> Function(Map<String, Set<Object>> result) onConfirmed,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _GroupedCheckboxDialog(
      title: title,
      groups: groups,
      onConfirmed: onConfirmed,
    ),
  );
}

class CheckboxGroup {
  final String key;
  final String title;
  final List<Object> values;
  final Set<Object> initialSelected;
  final String Function(Object) labelOf;

  CheckboxGroup({
    required this.key,
    required this.title,
    required this.values,
    required this.labelOf,
    Set<Object>? initialSelected,
  }) : initialSelected = initialSelected ?? {};
}

class _GroupedCheckboxDialog extends HookWidget {
  const _GroupedCheckboxDialog({
    required this.title,
    required this.groups,
    required this.onConfirmed,
  });

  final String title;
  final List<CheckboxGroup> groups;
  final Future<void> Function(Map<String, Set<Object>> result) onConfirmed;

  @override
  Widget build(BuildContext context) {
    final selections = {
      for (final g in groups) g.key: useState<Set<Object>>({...g.initialSelected}),
    };

    void confirm() {
      final result = {
        for (final e in selections.entries) e.key: {...e.value.value},
      };
      Navigator.pop(context);
      onConfirmed(result); // async outside context
    }

    return AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: groups.map((g) {
            final state = selections[g.key]!;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: Text(g.title, style: Theme.of(context).textTheme.titleSmall),
                ),
                ...g.values.map((v) {
                  return CheckboxListTile(
                    dense: true,
                    value: state.value.contains(v),
                    title: Text(g.labelOf(v)),
                    onChanged: (checked) {
                      final next = {...state.value};
                      checked == true ? next.add(v) : next.remove(v);
                      state.value = next;
                    },
                  );
                }),
              ],
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(getLocalizations(context).cancel),
        ),
        ElevatedButton(
          onPressed: confirm,
          child: Text(getLocalizations(context).reset),
        ),
      ],
    );
  }
}
