import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_storage_store.dart';
import 'package:package_info_plus/package_info_plus.dart';

const int kSettingsExportFormatVersion = 1;

class SettingsTransferService {
  static Future<Map<String, dynamic>> buildExport({
    required bool exportApp,
    required bool exportStorage,
  }) async {
    final result = <String, dynamic>{
      'format': kSettingsExportFormatVersion, // const
    };

    if (exportApp) {
      result['app'] = useAppStore().exportToJson();
    }
    if (exportStorage) {
      result['storage'] = useStorageStore().exportToJson();
    }

    return result;
  }

  static Future<void> importFromJson(
    Map<String, dynamic> json, {
    required bool importApp,
    required bool importStorage,
    required bool overrideStorage,
  }) async {
    if (json['format'] != kSettingsExportFormatVersion) {
      throw Exception('Unsupported export format');
    }

    if (importApp && json['app'] != null) {
      await useAppStore().importFromJson(json['app']);
    }

    if (importStorage && json['storage'] != null) {
      await useStorageStore().importFromJson(
        json['storage'],
        override: overrideStorage,
      );
    }
  }
}

Future<String> getDefaultExportFileName() async {
  final info = await PackageInfo.fromPlatform();
  final appId = info.packageName; // e.g. com.example.iris
  return '${appId}_settings_${DateTime.now().millisecondsSinceEpoch}.json';
}

Future<void> exportToFile(String jsonString, String defaultName) async {
  final bytes = utf8.encode(jsonString);

  await FilePicker.platform.saveFile(
    dialogTitle: 'Save settings export',
    fileName: defaultName,
    type: FileType.custom,
    allowedExtensions: ['json'],
    bytes: Uint8List.fromList(bytes),
  );
}

Future<String?> importFromFile() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['json'],
    withData: true,
  );

  if (result == null || result.files.isEmpty) return null;

  final file = result.files.single;

  if (file.bytes != null) {
    return utf8.decode(file.bytes!);
  }

  if (file.path != null) {
    return await File(file.path!).readAsString();
  }

  return null;
}
