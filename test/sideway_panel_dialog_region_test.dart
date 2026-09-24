import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/meta_settings/meta_settings_module.dart';
import 'package:iris/features/phone/one_handed_scrubber/controller/sideway_panel_layout.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/platform.dart';

import 'helpers/sqlite3_loader.dart';

/// The side-panel settings dialog must (a) never cover the side-type control
/// slider it edits, and (b) never persist while a slider / panel drag is in
/// flight — one commit at drag end is the whole budget.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqlite3Loaded();

  late AppDatabase db;
  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory());
    await DbModule.init(db);
  });
  tearDownAll(() => db.close);

  group('sidePanelRectForWindow', () {
    test('bottom-right phone anchor sits flush to the corner', () {
      final rect = sidePanelRectForWindow(
        windowSize: const Size(800, 360),
        anchor: Alignment.bottomRight,
        isPhone: true,
        widthPct: 40,
        heightPct: 90,
        widthPx: 380,
        heightPx: 420,
      );
      expect(rect.left, 800 - 320);
      expect(rect.top, 360 - 324);
      expect(rect.width, 320);
      expect(rect.height, 324);
    });
  });

  group('regionAvoidingPanel', () {
    test('drops the panel band entirely (no overlap possible)', () {
      const Rect panel = Rect.fromLTWH(480, 0, 320, 360);
      final Rect region = regionAvoidingPanel(
        screen: const Size(800, 360),
        safe: EdgeInsets.zero,
        panel: panel,
      );
      // Panel is on the right → the free strip is on the left.
      expect(region.right, lessThanOrEqualTo(panel.left));
      expect(region.overlaps(panel), isFalse);
    });

    test('picks the larger strip when the panel hugs the left edge', () {
      const Rect panel = Rect.fromLTWH(0, 0, 320, 360);
      final Rect region = regionAvoidingPanel(
        screen: const Size(800, 360),
        safe: EdgeInsets.zero,
        panel: panel,
      );
      expect(region.left, greaterThanOrEqualTo(panel.right));
      expect(region.overlaps(panel), isFalse);
    });

    test('falls back to the full safe screen without a panel', () {
      final Rect region = regionAvoidingPanel(
        screen: const Size(800, 360),
        safe: EdgeInsets.zero,
        panel: null,
      );
      expect(region, const Rect.fromLTRB(8, 8, 792, 352));
    });

    test('honours system-bar padding', () {
      final Rect region = regionAvoidingPanel(
        screen: const Size(800, 360),
        safe: const EdgeInsets.fromLTRB(40, 4, 4, 24),
        panel: null,
      );
      expect(region, const Rect.fromLTRB(48, 12, 788, 328));
    });
  });

  group('phonePanelMinPct', () {
    test('matches the rendered floor so the slider has no dead zone', () {
      expect(phonePanelMinPct(windowExtent: 800, minPx: kPanelMinPxW), 25);
      expect(phonePanelMinPct(windowExtent: 360, minPx: kPanelMinPxH),
          closeTo(44.44, 0.01));
    });

    test('never drops below the 10% slider floor', () {
      expect(phonePanelMinPct(windowExtent: 4000, minPx: kPanelMinPxW), 10);
    });

    test('degenerate window pins to 100 (empty draggable range)', () {
      expect(phonePanelMinPct(windowExtent: 100, minPx: kPanelMinPxW), 100);
      expect(phonePanelMinPct(windowExtent: 0, minPx: kPanelMinPxW), 100);
    });
  });

  group('persist-on-end', () {
    setUp(() async {
      await MetaSettingsModule.repo.clearValues();
    });

    test('slider drag frames stay memory-only; the commit writes once',
        () async {
      final store = AppStore();
      await store.setMetadataGate(true);
      for (int i = 0; i < 20; i++) {
        await store.updateSidewayPanelWidthPct(40 + i.toDouble(), persist: false);
      }
      var raw = await MetaSettingsModule.repo.loadRawValues();
      expect(raw.containsKey('slider.widthPct'), isFalse,
          reason: 'nothing may land mid-drag');
      expect(store.state.sidewayPanelWidthPct, 59,
          reason: 'memory still reflects the live drag');

      await store.updateSidewayPanelWidthPct(60);
      raw = await MetaSettingsModule.repo.loadRawValues();
      expect(double.parse(raw['slider.widthPct']!), 60);
    });

    test('dial + circle tuning persist only on commit', () async {
      final store = AppStore();
      await store.setMetadataGate(true);
      await store.updateRingDialHeightPct(0.55, persist: false);
      await store.updateCircleSliderScale(0.42, persist: false);
      var raw = await MetaSettingsModule.repo.loadRawValues();
      expect(raw.containsKey('dialring.ringDialHeightPct'), isFalse);
      expect(raw.containsKey('app.circleSliderScale'), isFalse);

      await store.updateRingDialHeightPct(0.8);
      await store.updateCircleSliderScale(0.6);
      raw = await MetaSettingsModule.repo.loadRawValues();
      expect(double.parse(raw['dialring.ringDialHeightPct']!), 0.8);
      expect(raw.containsKey('app.circleSliderScale'), isTrue);
    });

    test('persistSidewayPanelGeometry commits the current values once',
        () async {
      final store = AppStore();
      await store.setMetadataGate(true);
      debugIsMobilePlatformOverride = true;
      addTearDown(() => debugIsMobilePlatformOverride = null);

      await store.updateSidewayPanelWidthPct(55, persist: false);
      await store.updateSidewayPanelHeightPct(70, persist: false);
      var raw = await MetaSettingsModule.repo.loadRawValues();
      expect(raw.containsKey('slider.widthPct'), isFalse);

      await store.persistSidewayPanelGeometry();
      raw = await MetaSettingsModule.repo.loadRawValues();
      expect(double.parse(raw['slider.widthPct']!), 55);
      expect(double.parse(raw['slider.heightPct']!), 70);
      expect(raw.containsKey('slider.handleInsetH'), isTrue);
      expect(raw.containsKey('slider.handleInsetV'), isTrue);
    });

    test('bottom button-bar position is memory-only mid-drag, commits once',
        () async {
      final store = AppStore();
      await store.setMetadataGate(true);

      for (int i = 0; i < 10; i++) {
        await store.updateSidewayBarPos(i / 10, persist: false);
      }
      var raw = await MetaSettingsModule.repo.loadRawValues();
      expect(raw.containsKey('slider.barPos'), isFalse,
          reason: 'nothing may land mid-drag');
      expect(store.state.sidewayBarPos, closeTo(0.9, 1e-9),
          reason: 'memory still reflects the live drag');

      await store.updateSidewayBarPos(0.35);
      raw = await MetaSettingsModule.repo.loadRawValues();
      expect(double.parse(raw['slider.barPos']!), closeTo(0.35, 1e-9));
    });

    test('bottom button-bar position clamps to 0..1', () async {
      final store = AppStore();
      await store.setMetadataGate(true);
      await store.updateSidewayBarPos(2.5, persist: false);
      expect(store.state.sidewayBarPos, 1.0);
      await store.updateSidewayBarPos(-1, persist: false);
      expect(store.state.sidewayBarPos, 0.0);
    });
  });
}
