import 'package:flutter/material.dart' hide Chip;
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/store/use_storage_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/popups/storages/db/files_widget/files_db_controller.dart';
import 'package:iris/widgets/popups/storages/db/files_widget/files_sort_menu.dart';

class FilesToolbar extends HookWidget {
  const FilesToolbar({
    super.key,
    required this.controller,
    required this.storage,
  });

  final FilesDbController controller;
  final Storage storage;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    // Offline-grey: scan walks the live tree and can only fail without a
    // connection — the entry renders disabled with no reaction. Refresh
    // (the recovery path) and the rest of the toolbar stay enabled.
    final online = useStorageStore().select(
      context,
      (s) => s.storageConnectionStatus[storage.id] ?? true,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: t.back,
            icon: const Icon(Icons.arrow_back),
            onPressed: controller.back,
          ),
          PopupMenuButton<String>(
            tooltip: t.refresh,
            icon: const Icon(Icons.refresh),
            onSelected: (value) {
              if (value == 'refresh') {
                controller.refresh();
              } else if (value == 'scan_recursive') {
                controller.startRecursiveScan();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'refresh',
                child: Text(t.files_refresh),
              ),
              PopupMenuItem(
                value: 'scan_recursive',
                enabled: online,
                child: Text(t.files_scan_recursive),
              ),
            ],
          ),
          // Sorting
          const FilesSortMenu(),
          IconButton(
            tooltip: t.home,
            icon: const Icon(Icons.home),
            onPressed: controller.goHome,
          ),
          //  Favorites
          IconButton(
            tooltip: controller.currentFavorite != null ? t.remove_favorite : t.add_favorite,
            icon: Icon(controller.currentFavorite != null
                ? Icons.star_rounded
                : Icons.star_outline_rounded),
            onPressed: controller.toggleFavorite,
          ),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 4, right: 4),
              child: Text(
                controller.title,
                maxLines: 1,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  overflow: TextOverflow.ellipsis,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: '${t.close} ( Escape )',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}
