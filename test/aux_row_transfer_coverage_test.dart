import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/meta_settings/meta_settings_module.dart';
import 'package:iris/features/meta_settings/model/setting_domain.dart';
import 'package:iris/features/scenario_playback/model/enum/scenario_queue_layout.dart';
import 'package:iris/features/scenario_playback/model/enum/scenario_queue_profile.dart';
import 'package:iris/features/settings_transfer/engine/app_settings_coder.dart';
import 'package:iris/features/settings_transfer/model/import_resolution.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/store/keyboard_form_geometry.dart';
import 'package:iris/store/use_app_store.dart';

import 'helpers/sqlite3_loader.dart';

/// Transfer coverage for AUX (`<domain>.`) rows.
///
/// Every registered storage prefix must survive an export, except rows owned
/// by another coder (`tagplay.*`) or in the explicit [knownGaps] list. A new
/// AUX domain that forgets the coder allowlist turns this red instead of
/// silently dropping user data on restore.
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

  test('every registered AUX domain reaches the export', () async {
    final allPrefixes = kSettingDomains
        .map((d) => d.storagePrefix)
        .whereType<String>()
        .toSet();
    // `app.` travels via the AppState snapshot, not the AUX rows.
    allPrefixes.remove('app.');
    // TagPlay rows are owned by TagPlayCoder (see AppSettingsCoder header).
    allPrefixes.remove('tagplay.');
    // Deliberately uncovered today: the bg. domain carries per-media cache
    // rows (progress./ratioItem.<mediaKey>) whose migration scope is undecided.
    const knownGaps = {'bg.'};

    for (final p in allPrefixes) {
      await MetaSettingsModule.repo.saveRawValue('${p}probe', '1');
    }
    await MetaSettingsModule.repo.saveRawValue('tagplay.probe', '1');

    final encoded = await AppSettingsCoder().encode();
    final exportedKeys = <String>{
      for (final r in (encoded!['rows'] as List)) (r as Map)['key'] as String,
    };
    for (final p in allPrefixes.where((p) => !knownGaps.contains(p))) {
      expect(exportedKeys, contains('${p}probe'),
          reason: '$p must survive an export');
    }
    expect(exportedKeys, isNot(contains('tagplay.probe')),
        reason: 'tagplay.* is owned by TagPlayCoder, not AppSettingsCoder');
  });

  test('form.geometry import refreshes live AppState', () async {
    // Same hole the window domain had: the keyboard-form geometry is a `form.`
    // AUX row AND JsonKey-excluded from the legacy snapshot, so an import
    // could only ever reach the DB. The browser page-jump form reads it off
    // AppState, so without this refresh the imported position stayed
    // invisible until a restart.
    useAppStore();
    await useAppStore().initialized;
    final store = useAppStore();

    expect(store.state.keyboardFormGeometry, KeyboardFormGeometry.kDefault,
        reason: 'sanity: the probe must start at the centred default');

    final coder = AppSettingsCoder();
    final results = await coder.importSection(
      {
        'snapshot': <String, dynamic>{},
        'rows': [
          {'key': 'form.geometry', 'value': '0.2,0.85,0.4'},
        ],
      },
      resolution: TransferResolution.overwrite,
      skipErrors: true,
    );
    expect(results.any((r) => r.ok), isTrue);
    expect(
        store.state.keyboardFormGeometry,
        const KeyboardFormGeometry(
            offset: Offset(0.2, 0.85), widthFraction: 0.4),
        reason: 'the imported form position must be live without a restart');
  });

  test('snapshot-only import keeps live AUX prefs it does not carry', () async {
    // The snapshot round-trip drops every JsonKey-excluded field, so an
    // import whose snapshot omits the AUX prefs must re-hydrate them instead
    // of publishing defaults over the live state.
    useAppStore();
    await useAppStore().initialized;
    final store = useAppStore();

    await store.updateScenarioQueueLayout(
        ScenarioQueueProfile.desktop, ScenarioQueueLayout.v1);

    final coder = AppSettingsCoder();
    final results = await coder.importSection(
      {
        'snapshot': <String, dynamic>{'language': 'en'},
        'rows': <Map<String, String>>[],
      },
      resolution: TransferResolution.overwrite,
      skipErrors: true,
    );
    expect(results.any((r) => r.ok), isTrue);
    expect(
        store.state
            .scenarioQueueLayoutFor(ScenarioQueueProfile.desktop),
        ScenarioQueueLayout.v1,
        reason: 'a snapshot that carries no AUX keys must not reset them');
  });
}
