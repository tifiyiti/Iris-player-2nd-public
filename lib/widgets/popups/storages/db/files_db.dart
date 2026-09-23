import 'package:flutter/material.dart' hide Chip;
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/widgets/popups/storages/db/files_widget/files_breadcrumb.dart';
import 'package:iris/widgets/popups/storages/db/files_widget/files_db_controller.dart';
import 'package:iris/widgets/popups/storages/db/files_widget/files_list_view.dart';
import 'package:iris/widgets/popups/storages/db/files_widget/files_toolbar.dart';

class FilesDb extends HookWidget {
  const FilesDb({super.key, required this.storage});

  final Storage storage;

  @override
  Widget build(BuildContext context) {
    final controller = useFilesDbController(context, storage);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: FilesListView(controller: controller, storage: storage),
        ),
        FilesBreadcrumb(controller: controller, storage: storage),
        Divider(
          height: 0,
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
        ),
        FilesToolbar(controller: controller, storage: storage),
      ],
    );
  }
}
