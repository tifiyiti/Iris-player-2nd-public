import 'dart:io';

import 'package:flutter/material.dart' hide Chip;
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/globals.dart' as globals;
import 'package:iris/models/file.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/request_storage_permission.dart';
import 'package:iris/widgets/popups/storages/db/files_widget/file_list_tile.dart';
import 'package:iris/widgets/popups/storages/db/files_widget/files_db_controller.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class FilesListView extends HookWidget {
  const FilesListView({
    super.key,
    required this.controller,
    required this.storage,
  });

  final FilesDbController controller;
  final Storage storage;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);

    // Permission handling
    if (Platform.isAndroid &&
        globals.storagePermissionStatus != PermissionStatus.granted &&
        storage is LocalStorage) {
      return Center(
        child: ElevatedButton(
          onPressed: () async {
            await requestStoragePermission();
            controller.refresh();
          },
          child: Text(t.grant_storage_permission),
        ),
      );
    }

    if (controller.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (controller.isError) {
      return Center(child: Text(t.unable_to_fetch_files));
    }

    if (controller.files.isEmpty) {
      return const Center();
    }

    return Card(
      color: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: ScrollablePositionedList.builder(
        itemScrollController: controller.itemScrollController,
        scrollOffsetController: controller.scrollOffsetController,
        itemPositionsListener: controller.itemPositionsListener,
        scrollOffsetListener: controller.scrollOffsetListener,
        //
        itemCount: controller.files.length,
        itemBuilder: (_, index) {
          final file = controller.files[index];

          return FileListTile(
            file: file,
            onTap: () => _handleTap(context, controller.files, file, index),
          );
        },
      ),
    );
  }

  void _handleTap(
    BuildContext context,
    List<FileItem> files,
    FileItem file,
    int index,
  ) {
    if (file.isDir && file.name.isNotEmpty) {
      controller.openDirectory(file.name);
      return;
    }

    if (file.isPlayable) {
      controller.play(files, index);
      Navigator.pop(context);
    }
  }
}
