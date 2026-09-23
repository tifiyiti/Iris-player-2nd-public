import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/meta_settings/contributions/settings_catalog.dart';
import 'package:iris/features/meta_settings/engine/engine_host.dart';
import 'package:iris/features/meta_settings/engine/settings_engine.dart';
import 'package:iris/features/meta_settings/model/enum/settings_section.dart';
import 'package:iris/features/meta_settings/model/enum/setting_value_type.dart';
import 'package:iris/features/meta_settings/model/enum/setting_widget_kind.dart';
import 'package:iris/features/meta_settings/model/setting_def.dart';
import 'package:iris/models/store/app_state.dart';

/// Minimal in-memory host: applies through the same fromJson dialect as the
/// real store but never touches storage. Records funnel calls for asserts.
class _FakeHost implements SettingsEngineHost {
  _FakeHost(this._state);

  AppState _state;
  final List<String> persistedFields = [];
  final List<bool> gateTransitions = [];

  @override
  AppState get currentState => _state;

  @override
  Future<AppState?> applyJsonField(String field, Object? jsonValue) async {
    try {
      final payload = _state.toJson();
      payload[field] = jsonValue;
      final next = AppState.fromJson(
        json.decode(json.encode(payload)) as Map<String, dynamic>,
      );
      _state = next;
      return next;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> persistSnapshot(AppState next) async {
    persistedFields.addAll(next.toJson().keys);
  }

  @override
  Future<void> setMetadataGate(bool value) async {
    gateTransitions.add(value);
    _state = _state.copyWith(useMetadataSettings: value);
  }
}

void main() {
  group('SettingsEngine.applyField', () {
    late _FakeHost host;

    setUp(() => host = _FakeHost(const AppState()));

    test('unknown field is rejected', () async {
      expect(
        await SettingsEngine.applyField(host, 'autoPlay', true),
        isFalse,
        reason: 'fields without defs are not metadata-writable',
      );
      expect(host.persistedFields, isEmpty);
    });

    test('code-managed fields stay absent from the catalog (writable=false '
        'equivalent)', () {
      final engine = SettingsEngine.defs.map((d) => d.key);
      expect(engine, isNot(contains('app.autoPlay')));
      expect(engine, isNot(contains('app.useScenarioDrivenPlayback')));
      expect(engine, isNot(contains('app.runtimeOrientation')));
    });

    test('gate field routes to setMetadataGate, not generic apply', () async {
      expect(await SettingsEngine.applyField(host, 'useMetadataSettings', true),
          isTrue);
      expect(host.gateTransitions, [true]);
      expect(host.state.useMetadataSettings, isTrue);
    });

    test('clamp is enforced end-to-end on a def-backed int field', () async {
      // app.seekStepSeconds moved from meta-settings to control-bar button
      // (horizontal slider dialog). Engine no longer carries that def; clamp
      // contract stays on the typed mutator and ValueGuard directly.
      // Validate the engine still clamps a representative int def via injection.
      const intDef = SettingDef(
        key: 'app.seekStepSeconds',
        section: SettingsSection.play,
        valueType: SettingValueType.int,
        defaultValue: '5',
        writable: true,
        clampMin: 1,
        clampMax: 120,
        widgetKind: SettingWidgetKind.slider,
        editorKey: 'seek_step_seconds',
        titleKey: 'seek_step_seconds',
        subtitleKey: 'seek_step_seconds_desc',
        sortOrder: 46,
      );
      expect(
        await SettingsEngine.applyField(host, 'seekStepSeconds', 0,
            catalog: {'seekStepSeconds': intDef}),
        isTrue,
      );
      expect(host.state.seekStepSeconds, 1);
      expect(host.persistedFields, contains('seekStepSeconds'));
      // Catalog no longer ships seekStepSeconds — control bar owns it.
      expect(SettingsEngine.defForField('seekStepSeconds'), isNull);
    });

    test('enum whitelist rejects invalid names without persisting', () async {
      expect(
        await SettingsEngine.applyField(host, 'playerBackend', 'bogus'),
        isFalse,
      );
      expect(host.persistedFields, isEmpty);
      expect(host.state.playerBackend, PlayerBackend.mediaKit);
    });

    test('valid enum write persists and lands in state', () async {
      expect(
        await SettingsEngine.applyField(host, 'themeMode', 'dark'),
        isTrue,
      );
      expect(host.state.themeMode, ThemeMode.dark);
      expect(host.persistedFields, contains('themeMode'));
    });

    test('writable:false defs are rejected even when present', () async {
      const locked = SettingDef(
        key: 'app.language',
        section: SettingsSection.general,
        valueType: SettingValueType.string,
        defaultValue: 'system',
        writable: false,
        widgetKind: SettingWidgetKind.custom,
        editorKey: 'language',
        titleKey: 'language',
        sortOrder: 1,
      );
      final ok = await SettingsEngine.applyField(
        host,
        'language',
        'zh',
        catalog: {'language': locked},
      );
      expect(ok, isFalse);
      expect(host.state.language, 'system');
    });
  });

  group('catalog authority', () {
    test('engine merges ALL contributions (App + Scan), not a subset', () {
      final keys = SettingsEngine.defs.map((d) => d.key).toSet();
      expect(keys, contains('scan.autoCloseDelay'),
          reason: 'engine and renderer must validate/consume ONE catalog; '
              'a diverged engine copy lets duplicate-key bugs slip through');
      expect(keys, contains('app.playerBackend'));
      expect(keys, SettingsCatalog.defs.map((d) => d.key).toSet());
    });

    test('engine field index stays scoped to the app.* dialect', () {
      expect(SettingsEngine.defForField('autoCloseDelay'), isNull,
          reason: 'scan.* rows are owned by ScanStateBridge, not the engine');
      expect(SettingsEngine.defForField('themeMode'), isNotNull);
    });
  });
}

extension on _FakeHost {
  AppState get state => _state;
}
