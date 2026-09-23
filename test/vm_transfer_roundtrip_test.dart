import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/settings_transfer/engine/app_settings_coder.dart';
import 'package:iris/features/settings_transfer/model/import_resolution.dart';
import 'package:iris/features/virtual_media/model/enum/vm_enums.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/store/use_app_store.dart';

import 'helpers/sqlite3_loader.dart';

/// Imported `virtualmedia.*` AUX rows must go live without a restart:
/// the coder refreshes the AppState snapshot after upserting rows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqlite3Loaded();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  setUpAll(() async {
    await DbModule.init(AppDatabase(NativeDatabase.memory()));
  });

  test('virtualmedia row import refreshes live AppState', () async {
    useAppStore();
    await useAppStore().initialized;

    await useAppStore().updateVmCrossSegmentDragStrategy(
        VmCrossSegmentDragStrategy.directSwitch);

    final coder = AppSettingsCoder();
    final results = await coder.importSection(
      {
        'snapshot': <String, dynamic>{},
        'rows': [
          {'key': 'virtualmedia.crossDragStrategy', 'value': 'previewOnRelease'},
        ],
      },
      resolution: TransferResolution.overwrite,
      skipErrors: true,
    );
    expect(results.any((r) => r.ok), isTrue);
    expect(useAppStore().state.vmCrossSegmentDragStrategy,
        VmCrossSegmentDragStrategy.previewOnRelease);
  });
}
