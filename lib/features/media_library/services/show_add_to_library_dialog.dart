import 'package:flutter/material.dart';
import 'package:iris/features/media_library/model/db/adapters/media_library.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/utils/get_localizations.dart';

/// Standalone dialog to pick a target library.
///
/// Returns the selected library ID, or null if cancelled.
/// [excludeIds] — library IDs to hide (e.g., the current library).
Future<String?> showAddToLibraryDialog(
  BuildContext context, {
  List<String> excludeIds = const [],
}) async {
  final libraries = await DbModule.libraryRepo.getLibraries();
  // The hosting popup may have been dismissed while the DB read was in
  // flight; showing a dialog on a dead context throws.
  if (!context.mounted) return null;
  final t = getLocalizations(context);
  final candidates = libraries
      .where((lib) => lib.isUser && !excludeIds.contains(lib.id))
      .toList();

  if (candidates.isEmpty) {
    await showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(t.lib_no_libraries_title),
        content: Text(t.lib_create_first_hint),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(t.ok),
          ),
        ],
      ),
    );
    return null;
  }

  return showDialog<String>(
    context: context,
    builder: (_) => SimpleDialog(
      title: Text(t.lib_add_to_library),
      children: candidates
          .map(
            (lib) => SimpleDialogOption(
              onPressed: () => Navigator.pop(context, lib.id),
              child: Row(
                children: [
                  const Icon(Icons.video_library, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      lib.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    ),
  );
}
