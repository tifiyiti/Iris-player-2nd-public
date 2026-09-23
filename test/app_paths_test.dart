import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/utils/app_paths.dart';
import 'package:path/path.dart' as p;

void main() {
  group('resolvePortableLayout', () {
    test('non-Windows platforms never go portable', () {
      expect(
        resolvePortableLayout(
          platformSupported: false,
          forceDisabled: false,
          storeSandboxed: false,
          markerExists: true,
          exeDirPath: r'C:\app',
        ),
        isNull,
      );
    });

    test('env escape hatch (IRIS_NO_PORTABLE=1) disables portable mode', () {
      expect(
        resolvePortableLayout(
          platformSupported: true,
          forceDisabled: true,
          storeSandboxed: false,
          markerExists: true,
          exeDirPath: r'C:\app',
        ),
        isNull,
      );
    });

    test('MSIX sandbox (WindowsApps) never goes portable', () {
      expect(
        resolvePortableLayout(
          platformSupported: true,
          forceDisabled: false,
          storeSandboxed: true,
          markerExists: true,
          exeDirPath: r'C:\Program Files\WindowsApps\22P.IRISplayer\app',
        ),
        isNull,
      );
    });

    test('missing marker file means installed mode', () {
      expect(
        resolvePortableLayout(
          platformSupported: true,
          forceDisabled: false,
          storeSandboxed: false,
          markerExists: false,
          exeDirPath: r'C:\app',
        ),
        isNull,
      );
    });

    test('marker present resolves userdata root next to the exe', () {
      final layout = resolvePortableLayout(
        platformSupported: true,
        forceDisabled: false,
        storeSandboxed: false,
        markerExists: true,
        exeDirPath: r'C:\app',
      );
      expect(layout, isNotNull);
      expect(p.normalize(layout!.rootPath), p.normalize(r'C:\app\userdata'));
    });

    test('layout exposes stable db and settings sub-paths', () {
      final layout = resolvePortableLayout(
        platformSupported: true,
        forceDisabled: false,
        storeSandboxed: false,
        markerExists: true,
        exeDirPath: '/opt/iris',
      )!;
      expect(p.normalize(layout.dbDirPath), p.normalize('/opt/iris/userdata/db'));
      expect(
        p.normalize(layout.settingsDirPath),
        p.normalize('/opt/iris/userdata/settings'),
      );
    });
  });

  group('AppPaths.init', () {
    late Directory tempDir;
    late Directory exeDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('iris_paths_test');
      exeDir = Directory(p.join(tempDir.path, 'IRIS'));
      await exeDir.create(recursive: true);
      AppPaths.resetForTest();
    });

    tearDown(() async {
      AppPaths.resetForTest();
      await tempDir.delete(recursive: true);
    });

    test('no marker file -> installed mode, no root created', () async {
      await AppPaths.init(exeDirOverride: exeDir);

      expect(AppPaths.isPortable, isFalse);
      expect(AppPaths.layout, isNull);
      expect(AppPaths.fallbackReason, isNull);
      expect(Directory(p.join(exeDir.path, 'userdata')).existsSync(), isFalse);
    });

    test('marker file -> portable mode with created root dirs', () async {
      await File(p.join(exeDir.path, AppPaths.markerFileName)).create();

      await AppPaths.init(exeDirOverride: exeDir);

      expect(AppPaths.isPortable, isTrue);
      expect(AppPaths.fallbackReason, isNull);
      final layout = AppPaths.layout!;
      expect(
        p.normalize(layout.rootPath),
        p.normalize(p.join(exeDir.path, 'userdata')),
      );
      expect(Directory(layout.dbDirPath).existsSync(), isTrue);
      expect(Directory(layout.settingsDirPath).existsSync(), isTrue);
    });

    test('unwritable root degrades to installed mode with reason', () async {
      // Occupy the would-be root path with a FILE so directory creation
      // fails and the writability probe can never succeed.
      await File(p.join(exeDir.path, 'userdata')).writeAsString('blocker');
      await File(p.join(exeDir.path, AppPaths.markerFileName)).create();

      await AppPaths.init(exeDirOverride: exeDir);

      expect(AppPaths.isPortable, isFalse);
      expect(AppPaths.layout, isNull);
      expect(AppPaths.fallbackReason, PortableFallbackReason.dataDirNotWritable);
    });
  });
}
