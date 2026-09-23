import 'package:flutter/material.dart' hide Chip;
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';

class FilesSortMenu extends HookWidget {
  const FilesSortMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);

    final sortBy = useAppStore().select(context, (s) => s.sortBy);
    final sortOrder = useAppStore().select(context, (s) => s.sortOrder);
    final folderFirst = useAppStore().select(context, (s) => s.folderFirst);

    return PopupMenuButton(
      clipBehavior: Clip.hardEdge,
      constraints: const BoxConstraints(minWidth: 200),
      tooltip: t.sort,
      icon: const Icon(Icons.sort_rounded),
      itemBuilder: (_) => [
        _sortItem(context, t.name, SortBy.name, sortBy, sortOrder),
        _sortItem(context, t.size, SortBy.size, sortBy, sortOrder),
        _sortItem(context, t.last_modified, SortBy.lastModified, sortBy, sortOrder),
        PopupMenuItem(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(t.folder_first),
              Checkbox(
                value: folderFirst,
                onChanged: (_) {
                  useAppStore().updateFolderFirst(!folderFirst);
                  Navigator.pop(context);
                },
              )
            ],
          ),
        ),
      ],
    );
  }

  PopupMenuItem _sortItem(
    BuildContext context,
    String label,
    SortBy target,
    SortBy current,
    SortOrder order,
  ) {
    return PopupMenuItem(
      child: ListTile(
        mouseCursor: SystemMouseCursors.click,
        title: Text(label),
        trailing: current == target
            ? Icon(order == SortOrder.asc ? Icons.arrow_upward : Icons.arrow_downward)
            : null,
      ),
      onTap: () {
        useAppStore().updateSortBy(target);
        useAppStore().updateSortOrder(
          current == target && order == SortOrder.asc ? SortOrder.desc : SortOrder.asc,
        );
      },
    );
  }
}
