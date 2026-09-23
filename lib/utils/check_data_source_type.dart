import 'dart:io';
import 'package:iris/models/file.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:video_player/video_player.dart';

export 'package:video_player/video_player.dart' show DataSourceType;

DataSourceType checkDataSourceType(FileItem file) {
  if (Platform.isAndroid && file.uri.startsWith('content://')) {
    return DataSourceType.contentUri;
  }

  switch (file.storageType) {
    case StorageType.internal:
    case StorageType.network:
    case StorageType.sdcard:
    case StorageType.usb:
      return DataSourceType.file;
    case StorageType.webdav:
    case StorageType.ftp:
    case StorageType.none:
      return DataSourceType.network;
  }
}
