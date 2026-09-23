import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/meta_settings/bridge/state_bridge.dart';
import 'package:iris/features/meta_settings/meta_settings_module.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_app_store.dart';

import 'helpers/sqlite3_loader.dart';

/// Gate rollback contract (legacy <-> meta round-trip).
///
/// The user flow this pins: a meta-era install turns the gate OFF to run in
/// legacy mode, then turns it back ON and expects every meta-era preference
/// (including the JsonKey-excluded AUX-only domains) to be intact — and to
/// come back WITHOUT a restart.
///
///  1. gate-OFF clears ONLY the `app.*` snapshot rows (blob is authoritative);
///     AUX-only rows (`dialring.*`, `browse.*`, `playback.*`, `keybind.*`, …)
///     survive because the blob can never rebuild them;
///  2. gate-ON re-hydrates those rows onto the live state immediately;
///  3. a cold boot over the same rows restores them too;
///  4. the injected write gate blocks AUX writes while the gate is OFF so a
///     hidden legacy path can never clobber the preserved data.
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
    MetaSettingsModule.writeGate = null;
    await MetaSettingsModule.repo.clearValues();
    store = AppStore();
    // Install default is gate ON — exercise the OFF→ON transition.
    await store.setMetadataGate(false);
  });

  tearDown(() {
    MetaSettingsModule.writeGate = null;
  });

  tearDownAll(() => db.close());

  Future<Map<String, String>> rows() => MetaSettingsModule.repo.loadRawValues();

  /// Seeds one app.* row plus four AUX-only domains through the real setters.
  Future<void> seedMixedState() async {
    await store.setMetadataGate(true);
    await store.updateLanguage('zh'); // app.* (blob-backed)
    await store.updateRingDialPalette(RingDialPalette.warm); // dialring.*
    await store.updateBrowseMediaScope(BrowseMediaScope.audioOnly); // browse.*
    await store.updateResumeOnStartup(false); // playback.*
    await store.updateKeybindOverridesJson('{"playPause":[]}'); // keybind.*
  }

  test('gate OFF clears only app.* and preserves every AUX-only row', () async {
    await seedMixedState();

    var raw = await rows();
    expect(raw.containsKey('app.language'), isTrue);
    expect(raw['dialring.ringDialPalette'], isNotNull);
    expect(raw['browse.mediaScope'], isNotNull);
    expect(raw['playback.resumeOnStartup'], isNotNull);
    expect(raw['keybind.overrides'], isNotNull);

    await store.setMetadataGate(false);

    raw = await rows();
    expect(
      raw.keys.where((k) => k.startsWith('app.')),
      isEmpty,
      reason: 'app.* is the rollback surface and must be cleared on gate OFF',
    );
    expect(raw['dialring.ringDialPalette'], isNotNull,
        reason: 'AUX-only domains are not in the blob; a wipe would be '
            'unrecoverable');
    expect(raw['browse.mediaScope'], 'audioOnly');
    expect(raw['playback.resumeOnStartup'], isNotNull);
    expect(raw['keybind.overrides'], isNotNull);
  });

  test('gate ON re-hydrates AUX rows onto the live state (no restart)',
      () async {
    await seedMixedState();
    await store.setMetadataGate(false);

    // Simulate a legacy cold boot: excluded fields are code defaults because
    // the blob cannot carry them and the gate was OFF at boot.
    store.set(store.state.copyWith(
      ringDialPalette: RingDialPalette.mono,
      browseMediaScope: BrowseMediaScope.all,
      resumeOnStartup: true,
      keybindOverridesJson: '{}',
    ));
    expect(store.state.ringDialPalette, RingDialPalette.mono);

    await store.setMetadataGate(true); // hot switch, SAME instance

    expect(store.state.ringDialPalette, RingDialPalette.warm);
    expect(store.state.browseMediaScope, BrowseMediaScope.audioOnly);
    expect(store.state.resumeOnStartup, isFalse);
    expect(store.state.keybindOverridesJson, '{"playPause":[]}');
  });

  test('cold boot: materialize + AUX apply restores rows after OFF->ON',
      () async {
    await seedMixedState();
    await store.setMetadataGate(false);
    await store.setMetadataGate(true);

    final base = StateBridge.materialize(await rows());
    expect(base, isNotNull, reason: 'gate-ON re-seeded the app.* mirror');

    final withAux = await store.applyKeybindRows(
      await store.applyPlaybackRows(
        await store.applyBrowseRows(
          await store.applyDialRingRows(base!),
        ),
      ),
    );

    expect(withAux.ringDialPalette, RingDialPalette.warm);
    expect(withAux.browseMediaScope, BrowseMediaScope.audioOnly);
    expect(withAux.resumeOnStartup, isFalse);
    expect(withAux.keybindOverridesJson, '{"playPause":[]}');
  });

  test('writeGate blocks AUX preference writes while the gate is OFF',
      () async {
    MetaSettingsModule.writeGate = () => false;

    await MetaSettingsModule.persistAuxRow('tagplay.pinOrder', '[9]');
    await MetaSettingsModule.saveBrowseRow('mediaScope', 'videoOnly');

    var raw = await rows();
    expect(raw.containsKey('tagplay.pinOrder'), isFalse,
        reason: 'persistAuxRow must respect the injected write gate');
    expect(raw.containsKey('browse.mediaScope'), isFalse,
        reason: 'typed _saveAux writers must respect the injected write gate');

    MetaSettingsModule.writeGate = () => true;
    await MetaSettingsModule.persistAuxRow('tagplay.pinOrder', '[9]');
    raw = await rows();
    expect(raw['tagplay.pinOrder'], '[9]');
  });
}
