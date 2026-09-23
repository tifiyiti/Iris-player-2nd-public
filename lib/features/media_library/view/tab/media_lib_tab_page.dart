import 'package:flutter/material.dart';
import 'package:iris/features/media_library/view/tab/dialogs/show_batch_create_library_dialog.dart';
import 'package:iris/features/media_library/view/tab/dialogs/show_create_library_dialog.dart';
import 'package:iris/features/media_library/view/tab/store/selection/use_media_lib_selection.dart';
import 'package:iris/features/media_library/view/tab/widget/media_lib_sort_menu.dart';
import 'package:iris/features/media_library/view/tab/widget/media_libs_page.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/interface/tab_page_module.dart';

class MediaLibTabPage implements TabPageModule {
  @override
  String title(BuildContext context) => 'MediaDb';

  @override
  Widget buildPage(BuildContext context) {
    return const MediaLibPage();
  }

  @override
  Widget? buildAction(
    BuildContext context,
  ) {
    final selection = useMediaLibSelectionStore().controller;

    return ListenableBuilder(
      listenable: selection,
      builder: (_, __) {
        if (selection.isSelecting) return const SizedBox.shrink();

        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MediaLibSortMenu(),
            SizedBox(width: 8),
            _CreateLibraryButton(),
          ],
        );
      },
    );
  }
}

class _CreateLibraryButton extends StatelessWidget {
  const _CreateLibraryButton();

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    return PopupMenuButton<String>(
      icon: const Icon(Icons.add_rounded),
      onSelected: (value) async {
        switch (value) {
          case 'create':
            await showCreateLibraryDialog(context);
            break;

          case 'batch_create':
            await showBatchCreateLibraryDialog(context);
            break;
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'create',
          child: Text(t.lib_create_library),
        ),
        PopupMenuItem(
          value: 'batch_create',
          child: Text(t.lib_batch_create),
        ),
      ],
    );
  }
}
