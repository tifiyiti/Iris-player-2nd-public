import 'package:flutter/material.dart';
import 'package:iris/features/media_library/play_queue/models/play_queue_source.dart';
import 'package:iris/models/file.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/widgets/dialogs/show_append_feedback_dialog.dart';

/// Appends [files] to the (legacy) play queue and shows a before/after feedback
/// dialog (v14-D2) so the user knows the append landed. The queue count is the
/// play queue's `state.playQueue.length`, measured once before and once after
/// the append. [prepend] preserves the existing "insert at beginning" behavior.
Future<void> appendToPlayQueueWithFeedback(
  BuildContext context, {
  required List<FileItem> files,
  required bool prepend,
}) async {
  if (files.isEmpty) return;
  final store = usePlayQueueStore();
  final before = store.state.playQueue.length;
  final items = files
      .asMap()
      .entries
      .map((e) => PlayQueueItem(file: e.value, index: e.key))
      .toList();
  await store.appendSource(PlayQueueSource.explicit(items: items), prepend: prepend);
  final after = store.state.playQueue.length;
  if (!context.mounted) return;
  await showAppendFeedbackDialog(
    context,
    appended: files,
    beforeCount: before,
    afterCount: after,
  );
}
