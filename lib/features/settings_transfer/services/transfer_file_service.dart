import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:iris/features/settings_transfer/engine/platform_key_policy.dart';
import 'package:package_info_plus/package_info_plus.dart';

Future<String> getDefaultTransferFileName({bool encrypted = false, String? platform}) async {
  String appId = 'iris';
  try {
    final info = await PackageInfo.fromPlatform();
    appId = info.packageName;
  } catch (_) {}
  final ts = DateTime.now().millisecondsSinceEpoch;
  final suffix = encrypted ? '_encrypted' : '';
  // Platform segment tells phone/desktop files apart at a glance when
  // sharing across devices (e.g. iris_transfer_windows_<ts>.json).
  final seg = platform ?? currentTransferPlatformName;
  return '${appId}_transfer_${seg}_${ts}$suffix.json';
}

Future<void> saveTransferFile(String jsonString, String defaultName) async {
  final bytes = utf8.encode(jsonString);
  await FilePicker.platform.saveFile(
    dialogTitle: 'Save transfer file',
    fileName: defaultName,
    type: FileType.custom,
    allowedExtensions: ['json'],
    bytes: Uint8List.fromList(bytes),
  );
}

Future<String?> pickTransferFile() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['json'],
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;
  final file = result.files.single;
  if (file.bytes != null) return utf8.decode(file.bytes!);
  if (file.path != null) return File(file.path!).readAsString();
  return null;
}
