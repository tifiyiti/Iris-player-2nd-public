import 'package:flutter/material.dart' hide Chip;
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/models/file.dart';
import 'package:iris/widgets/popups/storages/db/files_widget/file_menu.dart';
import 'package:iris/widgets/popups/storages/db/files_widget/file_subtitle.dart';

class FileListTile extends HookWidget {
  const FileListTile({
    super.key,
    required this.file,
    required this.onTap,
  });

  final FileItem file;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
      visualDensity: const VisualDensity(horizontal: 0, vertical: -4),
      leading: _icon,
      title: Text(
        file.name,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: FileSubtitle(file: file),
      trailing: file.isPlayable ? FileMenu(file: file) : null,
      onTap: onTap,
    );
  }

  Widget get _icon {
    if (file.isDir && file.name.isNotEmpty) {
      return const Icon(Icons.folder_rounded);
    }

    switch (file.type) {
      case ContentType.video:
        return const Icon(Icons.movie_rounded);
      case ContentType.audio:
        return const Icon(Icons.audiotrack_rounded);
      case ContentType.image:
        return const Icon(Icons.image_rounded);
      default:
        return const Icon(Icons.file_copy_rounded);
    }
  }
}
