import 'package:flutter/material.dart';
import 'package:iris/features/media_library/view/tab/store/libs/use_media_libs_page_store.dart';
import 'package:iris/utils/get_localizations.dart';

Future<void> showBatchCreateLibraryDialog(
  BuildContext context,
) async {
  final patternController = TextEditingController(
    text: 'Library_{index}',
  );

  final countController = TextEditingController(
    text: '10',
  );

  final startIndexController = TextEditingController(
    text: '1',
  );

  final result = await showDialog<_BatchCreateResult>(
    context: context,
    builder: (_) {
      final t = getLocalizations(context);
      return AlertDialog(
        title: Text(t.lib_batch_create),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: patternController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: t.scn_batch_pattern,
                hintText: t.lib_batch_pattern_hint,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: countController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: t.scn_batch_count,
                hintText: t.lib_batch_count_hint,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: startIndexController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: t.scn_batch_start,
                hintText: t.scn_batch_start_hint,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () {
              final pattern = patternController.text.trim();

              final count = int.tryParse(
                countController.text.trim(),
              );

              final startIndex = int.tryParse(
                startIndexController.text.trim(),
              );

              if (pattern.isEmpty) {
                return;
              }

              if (count == null || count < 1) {
                return;
              }

              if (startIndex == null || startIndex < 0) {
                return;
              }

              Navigator.pop(
                context,
                _BatchCreateResult(
                  pattern: pattern,
                  count: count,
                  startIndex: startIndex,
                ),
              );
            },
            child: Text(t.scn_create),
          ),
        ],
      );
    },
  );

  if (result == null) {
    return;
  }

  final store = useMediaLibsStore();

  await store.createLibrariesBatch(
    pattern: result.pattern,
    count: result.count,
    startIndex: result.startIndex,
  );
}

class _BatchCreateResult {
  final String pattern;
  final int count;
  final int startIndex;

  const _BatchCreateResult({
    required this.pattern,
    required this.count,
    required this.startIndex,
  });
}
