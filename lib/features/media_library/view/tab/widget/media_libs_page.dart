import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/media_library/selection/selection_action.dart';
import 'package:iris/features/media_library/selection/selection_overlay_bar.dart';
import 'package:iris/features/media_library/services/add_sources_to_library.dart';
import 'package:iris/features/media_library/services/show_add_to_library_dialog.dart';
import 'package:iris/features/media_library/services/system_library_open_check.dart';
import 'package:iris/features/media_library/view/tab/store/libs/use_media_libs_page_store.dart';
import 'package:iris/features/media_library/view/tab/store/selection/use_media_lib_selection.dart';
import 'package:iris/features/media_library/view/tab/widget/media_lib_list_page.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/dialogs/show_message_dialog.dart';

class MediaLibPage extends HookWidget {
  const MediaLibPage({super.key});

  @override
  Widget build(BuildContext context) {
    final mediaStore = useMediaLibsStore();
    final media = mediaStore.select(context, (s) => s.runtime.libraries.map((e) => e.id).toList());
    final selectionStore = useMediaLibSelectionStore();
    final selection = selectionStore.controller;

    // open-check: maintain per-storage system libs + detached lib on tab entry.
    // Idempotent, re-entrancy guarded, and a no-op in legacy mode (D1/D15).
    useEffect(() {
      SystemLibraryOpenCheckService.openCheck().whenComplete(() {
        mediaStore.refresh();
      });
      return null;
    }, [mediaStore]);

    Future<void> handleDelete() async {
      final ids = selection.selected.toList();

      if (ids.isEmpty) {
        return;
      }

      final t = getLocalizations(context);
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) {
          return AlertDialog(
            title: Text(t.lib_delete_libraries_title),
            content: Text(t.lib_delete_libraries_body(ids.length)),
            actions: [
              Focus(
                autofocus: true,
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(context, false);
                  },
                  child: Text(t.cancel),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context, true);
                },
                child: Text(t.scn_delete),
              ),
            ],
          );
        },
      );

      if (ok != true) {
        return;
      }

      await mediaStore.deleteLibraries(ids);

      selection.exit();
    }

    Future<void> handleAddSources() async {
      final navigator = Navigator.of(context, rootNavigator: true);
      final selectedIds = selection.selected.toList();
      if (selectedIds.isEmpty) return;

      final allSources = <dynamic>[];
      for (final id in selectedIds) {
        final sources = await DbModule.sourcesRepository.getSources(id);
        allSources.addAll(sources);
      }
      // The page may have been popped while the DB reads were in flight.
      if (!context.mounted) return;
      final t = getLocalizations(context);

      if (allSources.isEmpty) {
        await showMessageDialog(
          navigator,
          message: t.lib_no_sources_to_copy,
          type: MessageDialogType.error,
        );
        return;
      }

      final targetId = await showAddToLibraryDialog(
        context,
        excludeIds: selectedIds,
      );
      if (targetId == null) return;

      final added = await addSourcesToLibrary(
        targetLibraryId: targetId,
        sources: allSources.cast(),
      );

      selection.exit();

      await showMessageDialog(
        navigator,
        message: t.lib_added_sources(added),
        type: MessageDialogType.success,
      );
    }

    return Stack(
      children: [
        const MediaLibListPage(),
        SelectionOverlayBar<String>(
          controller: selection,
          allItems: media,
          actions: [
            SelectionAction<String>(
              icon: const Icon(Icons.content_copy),
              onPressed: (_, __) async {
                await handleAddSources();
              },
            ),
            SelectionAction<String>(
              icon: const Icon(Icons.delete_outline),
              onPressed: (_, __) async {
                await handleDelete();
              },
            ),
          ],
        ),
      ],
    );
  }
}
