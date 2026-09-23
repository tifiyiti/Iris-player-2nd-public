import 'package:flutter/material.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';

/// Create scenario dialog with a top radio switching between:
/// - "Create one" (single name field)
/// - "Auto-generate" (batch: pattern + count + start index)
///
/// Batch defaults to 3 scenarios with a hard upper bound of 1000.
Future<void> showCreateScenarioDialog(
  BuildContext context,
) async {
  final nameController = TextEditingController();
  final patternController = TextEditingController(text: 'Scenario_{index}');
  final countController = TextEditingController(text: '3');
  final startIndexController = TextEditingController(text: '1');
  var batchMode = false;

  final result = await showDialog<_CreateScenarioResult>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final t = getLocalizations(ctx);
        return AlertDialog(
          title: Text(t.scn_create_title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioGroup<bool>(
                groupValue: batchMode,
                onChanged: (v) => setState(() => batchMode = v ?? false),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RadioListTile<bool>(
                      dense: true,
                      title: Text(t.scn_create_one),
                      value: false,
                    ),
                    if (!batchMode)
                      TextField(
                        controller: nameController,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: t.scn_name_label,
                          hintText: t.scn_name_hint_full,
                        ),
                      ),
                    RadioListTile<bool>(
                      dense: true,
                      title: Text(t.scn_batch_auto),
                      value: true,
                    ),
                  ],
                ),
              ),
              if (batchMode) ...[
                TextField(
                  controller: patternController,
                  decoration: InputDecoration(
                    labelText: t.scn_batch_pattern,
                    hintText: t.scn_batch_pattern_hint,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: countController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: t.scn_batch_count,
                    hintText: t.scn_batch_count_hint,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: startIndexController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: t.scn_batch_start,
                    hintText: t.scn_batch_start_hint,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(t.scn_cancel),
            ),
            FilledButton(
              onPressed: () {
                if (!batchMode) {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;
                  Navigator.pop(ctx, _CreateScenarioResult(name: name));
                  return;
                }

                final pattern = patternController.text.trim();
                final count = int.tryParse(countController.text.trim());
                final startIndex = int.tryParse(startIndexController.text.trim());
                if (pattern.isEmpty || count == null || count < 1) return;
                if (startIndex == null || startIndex < 0) return;
                if (count > 1000) return;

                Navigator.pop(ctx, _CreateScenarioResult(
                  pattern: pattern,
                  count: count,
                  startIndex: startIndex,
                ));
              },
              child: Text(t.scn_create),
            ),
          ],
        );
      },
    ),
  );

  if (result == null) return;

  final store = usePlaybackScenarioStore();
  if (result.name != null) {
    await store.createScenario(result.name!);
  } else {
    await store.createScenarioBatch(
      pattern: result.pattern!,
      count: result.count!,
      startIndex: result.startIndex!,
    );
  }
}

class _CreateScenarioResult {
  final String? name;
  final String? pattern;
  final int? count;
  final int? startIndex;

  const _CreateScenarioResult({
    this.name,
    this.pattern,
    this.count,
    this.startIndex,
  });
}
