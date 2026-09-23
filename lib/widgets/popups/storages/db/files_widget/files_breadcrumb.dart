import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_breadcrumb/flutter_breadcrumb.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/enums/breadcrumb_start_side.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/widgets/popups/storages/db/files_widget/files_db_controller.dart';

class FilesBreadcrumb extends StatelessWidget {
  const FilesBreadcrumb({
    super.key,
    required this.controller,
    required this.storage,
  });

  final FilesDbController controller;
  final Storage storage;

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.of(context).orientation;
    final store = useAppStore();

    final breadcrumbPortrait = store.select(context, (s) => s.breadcrumbStartPortrait);
    final breadcrumbLandscape = store.select(context, (s) => s.breadcrumbStartLandscape);

    final startSide =
        orientation == Orientation.portrait ? breadcrumbPortrait : breadcrumbLandscape;

    final startRight = startSide == BreadcrumbStartSide.right;

    final currentPath = controller.currentPath;

    final displayParts = [
      storage.basePath.length > 1 ? currentPath.first : storage.name,
      ...currentPath.sublist(1),
    ];

    final items = startRight ? displayParts.reversed.toList() : displayParts;

    final icon = startRight ? Icons.chevron_left_rounded : Icons.chevron_right_rounded;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Align(
        alignment: startRight ? Alignment.centerRight : Alignment.centerLeft,
        child: BreadCrumb.builder(
          itemCount: items.length,
          overflow: Platform.isAndroid || Platform.isIOS
              ? ScrollableOverflow(reverse: startRight)
              : const WrapOverflow(),
          builder: (index) {
            final realIndex = startRight ? displayParts.length - index - 1 : index;

            return BreadCrumbItem(
              content: TextButton(
                child: Text(items[index]),
                onPressed: () {
                  controller.openPathIndex(realIndex);
                },
              ),
            );
          },
          divider: Icon(
            icon,
            color: Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(222),
          ),
        ),
      ),
    );
  }
}
