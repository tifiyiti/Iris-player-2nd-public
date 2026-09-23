import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/engine/background_playback_engine.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/store/app_state.dart' show PlayerBackend;

import 'helpers/sqlite3_loader.dart';

FileItem _f(String key) => FileItem(name: key, uri: 'file:///$key', path: [key]);

void main() {
  ensureSqlite3Loaded();
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  // `open` resolves the storage record, which reads `DbModule.storageRepo`.
  late AppDatabase moduleDb;
  setUpAll(() async {
    moduleDb = AppDatabase(NativeDatabase.memory());
    await DbModule.init(moduleDb);
  });
  tearDownAll(() => moduleDb.close());

  group('BackgroundPlaybackEngine stop (P0-2)', () {
    test('stop unloads the file but keeps the warm engine reusable',
        () async {
      final engine = BackgroundPlaybackEngine(
        backend: PlayerBackend.mediaKit,
        attachNative: false,
      );
      addTearDown(engine.dispose);

      await engine.open(_f('a'), autoplay: true);
      expect(engine.file?.name, 'a');

      await engine.stop();

      // True STOP: the decoder/file handle is released (no stale audio, no
      // stale resolver entry) while the warm Player instance itself survives
      // for the next open — no black-flash reconstruction.
      expect(engine.file, isNull);
      expect(engine.errorText, isNull);
      expect(engine.isPlaying, isFalse);
      expect(engine.position, Duration.zero);
    });
  });
}
