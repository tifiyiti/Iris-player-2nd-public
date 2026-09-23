import 'dart:io';
import 'package:iris/utils/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
final areaKeyLog = AreaKeyLog(LogKeys.legacyDb);

Future<bool> dataMigration() async {
  try {
    if (Platform.isWindows) {
      final String newDataPath = (await getApplicationSupportDirectory()).path;
      final String oldDataPath =
          p.normalize('$newDataPath/../../nini22p.iris/iris');
      areaKeyLog.i('newDataPath: $newDataPath');
      areaKeyLog.i('oldDataPath: $oldDataPath');
      final bool newDataExist =
          await File('$newDataPath/flutter_secure_storage.dat').exists();
      final bool oldDataExist =
          await File('$oldDataPath/flutter_secure_storage.dat').exists();
      if (!newDataExist && oldDataExist) {
        areaKeyLog.i('Find old data in $oldDataPath');
        final Directory oldDir = Directory(oldDataPath);
        final Directory newDir = Directory(newDataPath);

        if (await oldDir.exists()) {
          if (!await newDir.exists()) {
            await newDir.create(recursive: true);
          }

          await for (var entity in oldDir.list()) {
            if (entity is File) {
              final String newFilePath =
                  p.join(newDir.path, p.basename(entity.path));
              await entity.copy(newFilePath);
              areaKeyLog.i('Copied ${entity.path} to $newFilePath');
            }
          }
          areaKeyLog.i('Data migration completed');
          return true;
        }
      }
    }
  } catch (e) {
    return false;
  }

  return false;
}
