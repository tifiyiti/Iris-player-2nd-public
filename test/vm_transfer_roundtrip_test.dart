import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/scenario_playback/model/enum/scenario_queue_layout.dart';
import 'package:iris/features/scenario_playback/model/enum/scenario_queue_profile.dart';
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

  test('window row import refreshes live AppState', () async {
    // Same hole one domain over: the queue's layout / bar spot / breadcrumb are
    // `window.` AUX rows AND JsonKey-excluded from the legacy snapshot, so an
    // import could only ever reach the DB. A queue already on screen reads them
    // off AppState, so without this refresh the imported toolbar stayed
    // invisible until a restart.
    useAppStore();
    await useAppStore().initialized;
    final store = useAppStore();

    final profile = ScenarioQueueProfile.desktop;
    expect(store.state.scenarioQueueLayoutFor(profile),
        isNot(ScenarioQueueLayout.v1),
        reason: 'sanity: the probe must start somewhere other than the target');

    final coder = AppSettingsCoder();
    final results = await coder.importSection(
      {
        'snapshot': <String, dynamic>{},
        'rows': [
          {'key': 'window.scenarioQueueLayoutDesktop', 'value': 'v1'},
        ],
      },
      resolution: TransferResolution.overwrite,
      skipErrors: true,
    );
    expect(results.any((r) => r.ok), isTrue);
    expect(store.state.scenarioQueueLayoutFor(profile), ScenarioQueueLayout.v1,
        reason: 'the imported toolbar must be live without a restart');
  });
}
