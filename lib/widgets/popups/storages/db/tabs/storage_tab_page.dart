import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:iris/features/scenario_playback/actions/stay_mode_page_action.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/models/storages/volume_identity.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/path_conv.dart';
import 'package:iris/utils/platform.dart';
import 'package:iris/widgets/dialogs/show_folder_dialog.dart';
import 'package:iris/widgets/dialogs/show_ftp_dialog.dart';
import 'package:iris/widgets/dialogs/show_webdav_dialog.dart';
import 'package:iris/widgets/interface/tab_page_module.dart';
import 'package:iris/widgets/popups/storages/db/storages_db_list.dart';
import 'package:iris/widgets/popups/storages/db/storages_utils/storage_utils.dart';
import 'package:saf_util/saf_util.dart';

class StorageTabPage implements TabPageModule {
  @override
  String title(BuildContext context) => getLocalizations(context).storage;

  @override
  Widget buildPage(BuildContext context) => const StoragesDbList();

  @override
  Widget? buildAction(BuildContext context) {
    final t = getLocalizations(context);
    // v6-D34/D33: storagedb-level stay/pin toggle (default off). The play
    // surfaces (F-001/F-003/F-004) read `storagesDbStayOnPlay` to decide
    // whether a successful Override closes the popup.
    final pinStore = usePlaybackScenarioStore();
    final pinAction = buildStayModePageAction(
      stay: pinStore.storagesDbStayOnPlay,
      onToggle: () => pinStore
          .setStoragesDbStayOnPlay(!pinStore.storagesDbStayOnPlay),
      stayLabel: t.storages_stay_open,
      leaveLabel: t.storages_close_on_play,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: pinAction.label,
          icon: pinAction.icon,
          visualDensity: VisualDensity.compact,
          onPressed: pinAction.onPressed,
        ),
        PopupMenuButton<StorageType>(
          tooltip: t.add_storage,
          icon: const Icon(Icons.add_rounded),
          iconColor: Theme.of(context).colorScheme.onSurfaceVariant,
          clipBehavior: Clip.hardEdge,
          color: Theme.of(context).colorScheme.surface.withAlpha(250),
          onSelected: (type) => _handleStorageSelected(context, type),
          itemBuilder: (ctx) => [
            PopupMenuItem(
                value: StorageType.internal,
                child: Text(getLocalizations(ctx).storages_folder)),
            const PopupMenuItem(value: StorageType.webdav, child: Text('WebDAV')),
            const PopupMenuItem(value: StorageType.ftp, child: Text('FTP')),
          ],
        ),
      ],
    );
  }

  void _handleStorageSelected(BuildContext context, StorageType type) {
    switch (type) {
      case StorageType.internal:
      case StorageType.network:
      case StorageType.usb:
      case StorageType.sdcard:
        _pickLocalFolder(context, type);
        break;
      case StorageType.webdav:
        showWebDAVDialog(context);
        break;
      case StorageType.ftp:
        showFTPDialog(context);
        break;
      case StorageType.none:
        break;
    }
  }

  Future<void> _pickLocalFolder(BuildContext context, StorageType type) async {
    if (isAndroid) {
      final dir = await SafUtil().pickDirectory(persistablePermission: true);
      if (dir != null && context.mounted) {
        showFolderDialog(
          context,
          storage: makeLocalStorage(
            type: type,
            name: dir.name,
            basePath: [dir.uri],
          ),
        );
      }
    } else {
      final path = await FilePicker.platform.getDirectoryPath();
      if (path != null && context.mounted) {
        final segments = pathConv(path);
        final volumeId = await VolumeIdentity.of(segments.join('/'));
        if (!context.mounted) return;
        showFolderDialog(
          context,
          storage: makeLocalStorage(
            type: type,
            name: segments.last,
            basePath: segments,
            volumeId: volumeId,
          ),
        );
      }
    }
  }
}
