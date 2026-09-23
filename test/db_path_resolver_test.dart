import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:path/path.dart' as p;

void main() {
  group('resolveDbFilePath', () {
    const dbFileName = 'com.example.iris_storages.db';

    test('Android uses the platform databases directory', () {
      final path = resolveDbFilePath(
        isAndroid: true,
        isPortable: true, // irrelevant on Android
        portableRootPath: '/ignored/userdata',
        androidDatabasesPath: '/data/data/com.example.iris/databases',
        documentsPath: '/ignored/Documents',
        dbFileName: dbFileName,
      );
      expect(
        p.normalize(path),
        p.normalize('/data/data/com.example.iris/databases/$dbFileName'),
      );
    });

    test('portable Windows puts the db under <userdata>/db', () {
      final path = resolveDbFilePath(
        isAndroid: false,
        isPortable: true,
        portableRootPath: r'D:\IRIS\userdata',
        androidDatabasesPath: '',
        documentsPath: r'C:\Users\u\Documents',
        dbFileName: dbFileName,
      );
      expect(
        p.normalize(path),
        p.normalize(r'D:\IRIS\userdata\db') +
            p.separator +
            dbFileName,
      );
    });

    test('installed Windows keeps the Documents location', () {
      final path = resolveDbFilePath(
        isAndroid: false,
        isPortable: false,
        portableRootPath: null,
        androidDatabasesPath: '',
        documentsPath: r'C:\Users\u\Documents',
        dbFileName: dbFileName,
      );
      expect(
        p.normalize(path),
        p.normalize(r'C:\Users\u\Documents') + p.separator + dbFileName,
      );
    });

    test('portable without a resolved root defensively falls back '
        'to Documents', () {
      final path = resolveDbFilePath(
        isAndroid: false,
        isPortable: true,
        portableRootPath: null,
        androidDatabasesPath: '',
        documentsPath: r'C:\Users\u\Documents',
        dbFileName: dbFileName,
      );
      expect(
        p.normalize(path),
        p.normalize(r'C:\Users\u\Documents') + p.separator + dbFileName,
      );
    });
  });
}
