import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/meta_settings/bridge/scan_state_bridge.dart';
import 'package:iris/features/meta_settings/bridge/state_bridge.dart';
import 'package:iris/features/meta_settings/engine/settings_engine.dart';
import 'package:iris/features/meta_settings/meta_settings_module.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/store/use_app_store.dart';

import 'helpers/sqlite3_loader.dart';

/// Integration tests for THE write funnel (P0 regressions).
///
/// These pin the contract that motivated the v2 engine:
///  1. typed-mutator (dialog-driven) edits land in setting_values while the
///     gate is ON — the prototype lost them on restart;
///  2. enabling the gate persists useMetadataSettings=true IMMEDIATELY — the
///     prototype snapshotted before flipping and a reboot reverted the gate;
///  3. disabling clears the mirror (lossless rollback surface);
///  4. sync-OFF keeps rows fresh (blob freeze is invisible to the DB side);
///  5. rows materialize back to a full state — the exact read path a reboot
///     takes.
///
/// Blob assertions are impossible here (no secure-storage plugin in widget
/// tests); blob behavior is covered by PersistPolicy unit tests + code review.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqlite3Loaded();

  late AppDatabase db;
  late AppStore store;

  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory());
    await DbModule.init(db);
  });

  setUp(() async {
    // Fresh table per test; store starts from defaults.
    await MetaSettingsModule.repo.clearValues();
    store = AppStore();
    // Install default is gate ON — these tests exercise the OFF→ON
    // transition, so seed OFF first.
    await store.setMetadataGate(false);
  });
  tearDownAll(() => db.close());

  Future<Map<String, String>?> rows() =>
      MetaSettingsModule.repo.loadRawValues();

  test('typed mutator (dialog path) dual-writes into DB under gate ON',
      () async {
    await store.setMetadataGate(true);
    await store.updateLanguage('zh');

    final mirror = (await rows())!;
    expect(mirror['app.language'], '"zh"',
        reason: 'dialog-driven edits must reach the DB mirror');
    expect(store.state.language, 'zh');

    // Restart proxy: the exact bridge call AppStore.load performs.
    final restored = StateBridge.materialize(mirror);
    expect(restored!.language, 'zh');
  });

  test(
      'enabling the gate stores useMetadataSettings=true immediately '
      '(enable-then-reboot durability)', () async {
    await store.setMetadataGate(true);
    expect((await rows())?['app.useMetadataSettings'], 'true');
  });

  test('disabling the gate clears the mirror after reverse-export', () async {
    await store.setMetadataGate(true);
    await store.updateLanguage('zh');
    await store.setMetadataGate(false);

    expect(await MetaSettingsModule.repo.hasAnyValue(), isFalse,
        reason: 'rows dropped for a clean rollback surface; the forced blob '
            'write carried the latest state (reverse export)');
    expect(store.state.useMetadataSettings, isFalse);
  });

  test('sync OFF: mutations keep landing in rows', () async {
    await store.setMetadataGate(true);
    // Flip the sync gate through the typed updater, like the Legacy 兼容
    // dialog does (requirement #5: the sync def moved inside that entry).
    await store.toggleSyncLegacyBlob();

    await store.updateThemeMode(ThemeMode.dark);

    final mirror = (await rows())!;
    expect(mirror['app.themeMode'], '"dark"');
    expect(mirror['app.syncLegacyBlob'], 'false');

    final restored = StateBridge.materialize(mirror)!;
    expect(restored.themeMode, ThemeMode.dark);
    expect(restored.syncLegacyBlob, isFalse);
    expect(restored.useMetadataSettings, isTrue);
  });

  test('incremental (diff) writes accumulate across mutations', () async {
    // The single-row upsert path must not lose earlier changes when the
    // baseline advances on each write.
    await store.setMetadataGate(true);
    await store.updateLanguage('zh');
    await store.updateThemeMode(ThemeMode.dark);
    await store.toggleSyncLegacyBlob();

    final mirror = (await rows())!;
    expect(mirror['app.language'], '"zh"');
    expect(mirror['app.themeMode'], '"dark"');
    expect(mirror['app.syncLegacyBlob'], 'false');
    // Full-state fields we never touched are still reconstructible.
    expect(StateBridge.materialize(mirror)!.language, 'zh');
  });

  test('engine rejections leave no mirror writes behind', () async {
    await store.setMetadataGate(true);
    final before = await rows();

    expect(await SettingsEngine.applyField(store, 'autoPlay', true), isFalse);
    expect(
      await SettingsEngine.applyField(store, 'playerBackend', 'bogus'),
      isFalse,
    );

    expect(await rows(), before,
        reason: 'rejected writes must not touch persistence');
  });

  test('auxiliary scan rows survive app.* snapshot rewrites', () async {
    await store.setMetadataGate(true);
    // The scan store mirrors its preference as a single auxiliary row.
    await MetaSettingsModule.persistAuxRow(
      ScanStateBridge.key,
      jsonEncode(3.5),
    );
    expect((await rows())?[ScanStateBridge.key], '3.5');

    // ANY app.* mutation replaces the full snapshot — it must stay scoped
    // to the app.* namespace and never touch auxiliary domains.
    await store.updateLanguage('zh');

    final mirror = (await rows())!;
    expect(mirror[ScanStateBridge.key], '3.5',
        reason: 'snapshot replacement is namespace-scoped to app.*; '
            'wiping scan.* would silently demote the DB from authority');
    expect(mirror['app.language'], '"zh"');
  });
}
