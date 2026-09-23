import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/meta_settings/meta_settings_module.dart';
import 'package:iris/features/phone/one_handed_scrubber/controller/phone_ring_dial_math.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_app_store.dart';

import 'helpers/sqlite3_loader.dart';

/// Dial-ring styling lives OUTSIDE the JSON persist world:
///
///  1. the styling fields never serialize into the legacy blob or the `app.%`
///     snapshot rows (`toJson` drops them, `fromJson` ignores stale keys);
///  2. under the metadata gate they round-trip through dedicated `dialring.`
///     Drift rows that survive `app.%` snapshot wipes;
///  3. with the gate OFF they stay memory-only (defaults).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqlite3Loaded();

  late AppDatabase db;

  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory());
    await DbModule.init(db);
  });
  tearDownAll(() => db.close);

  group('json exclusion', () {
    const populated = AppState(
      ringDialPalette: RingDialPalette.warm,
      ringDialHeightPct: 0.7,
      ringDialOuterRadius: 0.9,
      ringDialInnerRadius: 0.6,
      ringDialSide: DialSide.outer,
      ringDialRingSlotT: 0.4,
    );

    test('toJson omits every dial-ring styling field', () {
      final json = populated.toJson();
      const keys = <String>[
        'ringDialPalette',
        'ringDialHeightPct',
        'ringDialOuterRadius',
        'ringDialInnerRadius',
        'ringDialSide',
        'ringDialRingSlotT',
      ];
      for (final k in keys) {
        expect(json.containsKey(k), isFalse,
            reason: '$k must not leak into the persisted JSON world');
      }
    });

    test('fromJson ignores stale dial-ring keys and defaults to mono', () {
      final s = AppState.fromJson(const <String, dynamic>{
        'ringDialScale': 1.4, // removed knob from an older build
        'ringDialAxisGap': 20.0, // removed knob from an older build
        'ringDialPalette': 'rainbow',
        'ringDialWidthPct': 0.6, // removed knob (width ≡ panel width now)
        'ringDialBlockXPct': 80.0, // removed floating-block knob
        'ringDialRingCenterPct': 55.0, // superseded by slot ratios
      });
      expect(s.ringDialPalette, RingDialPalette.mono,
          reason: 'stale stored palette must not resurrect; default is mono');
      expect(s.ringDialSide, DialSide.inner,
          reason: 'styling fields are code-owned defaults at boot');
      expect(s.ringDialRingSlotT, 0.30,
          reason: 'default slot hugs the screen-centreline side');
    });
  });

  group('clamp contracts', () {
    test('height share is bounded to [0.30, 1.0]', () {
      expect(clampRingDialPct(0.2), 0.30);
      expect(clampRingDialPct(0.75), 0.75);
      expect(clampRingDialPct(1.4), 1.0);
    });

    test('corridor slot ratios are bounded to [0, 1]', () {
      expect(clampSlotT(-99), 0);
      expect(clampSlotT(0.425), 0.425);
      expect(clampSlotT(99), 1);
    });
  });

  group('dialring rows', () {
    setUp(() async {
      await MetaSettingsModule.repo.clearValues();
    });

    test('gate OFF keeps styling memory-only (no rows)', () async {
      final store = AppStore();
      // Install default is gate ON — this test pins the OFF degradation.
      store.set(store.state.copyWith(useMetadataSettings: false));
      await store.updateRingDialRingSlotT(0.7);

      expect(store.state.ringDialRingSlotT, 0.7);
      final raw = await MetaSettingsModule.repo.loadRawValues();
      expect(raw.keys.any((k) => k.startsWith('dialring.')), isFalse,
          reason: 'without the metadata gate nothing may be persisted');
    });

    test('updaters write dialring rows under gate ON and survive '
        'app.% snapshot wipes', () async {
      final store = AppStore();
      await store.setMetadataGate(true);
      await store.updateRingDialRingSlotT(0.8);
      await store.updateRingDialPalette(RingDialPalette.cold);
      await store.updateRingDialSide(DialSide.outer);

      // Any unrelated typed mutation replaces the whole `app.%` snapshot.
      await store.updateLanguage('zh');

      final raw = await MetaSettingsModule.repo.loadRawValues();
      expect(raw['dialring.ringDialRingSlotT'], '0.8');
      expect(raw['dialring.ringDialPalette'], 'cold');
      expect(raw['dialring.ringDialSide'], 'outer');
      expect(raw['app.language'], '"zh"');
      expect(raw.containsKey('app.ringDialRingSlotT'), isFalse,
          reason: 'styling must never enter the app.% snapshot');
      expect(store.state.ringDialRingSlotT, 0.8);
    });

    test('outer-radius update re-clamps the stored inner factor '
        '(both rows land)', () async {
      final store = AppStore();
      await store.setMetadataGate(true);
      await store.updateRingDialInnerRadius(0.787);
      await store.updateRingDialOuterRadius(0.82);

      final raw = await MetaSettingsModule.repo.loadRawValues();
      final inner = double.parse(raw['dialring.ringDialInnerRadius']!);
      expect(double.parse(raw['dialring.ringDialOuterRadius']!), 0.82);
      expect(inner, lessThanOrEqualTo(0.82 - 0.05),
          reason: 'inner factor must ride the outer bound (separation 0.05)');
    });

    test('restart proxy: applyDialRingRows rehydrates clamped overrides',
        () async {
      final store = AppStore();
      await store.setMetadataGate(true);
      await store.updateRingDialHeightPct(0.9);

      final reloaded =
          await AppStore().applyDialRingRows(AppState(useMetadataSettings: true));
      expect(reloaded.ringDialHeightPct, 0.9);
    });

    test('vm progress lock persists and defaults to ON when absent', () async {
      final store = AppStore();
      await store.setMetadataGate(true);
      // Flip away from the default so the round-trip is observable.
      await store.updateRingDialVmProgressLock(false);

      final raw = await MetaSettingsModule.repo.loadRawValues();
      expect(raw['dialring.ringDialVmProgressLock'], '0');

      final reloaded = await AppStore()
          .applyDialRingRows(const AppState(useMetadataSettings: true));
      expect(reloaded.ringDialVmProgressLock, isFalse);

      // No row → code default (the feature ships enabled).
      await MetaSettingsModule.repo.clearValues();
      final fresh = await AppStore().applyDialRingRows(const AppState());
      expect(fresh.ringDialVmProgressLock, isTrue);
    });

    test('corrupt rows degrade to defaults instead of throwing', () async {
      final store = AppStore();
      await store.setMetadataGate(true);
      await MetaSettingsModule.repo.saveRawValue(
          'dialring.ringDialSide', 'diagonal');

      final reloaded = await AppStore().applyDialRingRows(AppState());
      expect(reloaded.ringDialSide, DialSide.inner);
    });
  });
}
