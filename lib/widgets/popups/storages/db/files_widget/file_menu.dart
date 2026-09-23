import 'package:flutter/material.dart' hide Chip;
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/models/file.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/utils/get_localizations.dart';

class FileMenu extends HookWidget {
  const FileMenu({
    super.key,
    required this.file,
  });

  final FileItem file;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);

    return PopupMenuButton<_FileMenuAction>(
      clipBehavior: Clip.hardEdge,
      constraints: const BoxConstraints(minWidth: 200),
      onSelected: (action) {
        switch (action) {
          case _FileMenuAction.addToQueue:
            usePlayQueueStore().add([file]);
            break;
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: _FileMenuAction.addToQueue,
          child: Text(t.add_to_play_queue),
        ),
      ],
    );
  }
}

enum _FileMenuAction {
  addToQueue,
}
