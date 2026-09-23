import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:iris/globals.dart' as globals;
import 'package:permission_handler/permission_handler.dart';

Future<void> requestStoragePermission() async {
  if (!Platform.isAndroid) {
    return;
  }

  if (globals.storagePermissionStatus == PermissionStatus.granted) return;

  if (await isAndroid11OrHigher()) {
    final status = await Permission.manageExternalStorage.request();
    globals.storagePermissionStatus = status;
    if (status.isPermanentlyDenied) return;
  } else {
    final status = await Permission.storage.request();
    globals.storagePermissionStatus = status;
    if (status.isPermanentlyDenied) return;
  }
}

Future<bool> isAndroid11OrHigher() async {
  DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
  AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
  return androidInfo.version.sdkInt >= 30;
}
