import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/meta_settings/engine/persist_policy.dart';
import 'package:iris/models/store/app_state.dart';

void main() {
  group('PersistPolicy write matrix', () {
    test('legacy mode: blob only, regardless of sync gate', () {
      expect(
        PersistPolicy.targets(
          const AppState().copyWith(useMetadataSettings: false),
        ),
        (writeBlob: true, writeRows: false),
      );
      expect(
        PersistPolicy.targets(
          const AppState()
              .copyWith(useMetadataSettings: false, syncLegacyBlob: false),
        ),
        (writeBlob: true, writeRows: false),
      );
    });

    test('metadata mode + sync ON (default): dual-write', () {
      expect(
        PersistPolicy.targets(
          const AppState().copyWith(useMetadataSettings: true),
        ),
        (writeBlob: true, writeRows: true),
      );
    });

    test('metadata mode + sync OFF: rows only, blob frozen', () {
      expect(
        PersistPolicy.targets(
          const AppState()
              .copyWith(useMetadataSettings: true, syncLegacyBlob: false),
        ),
        (writeBlob: false, writeRows: true),
      );
    });
  });

  group('gate transition override', () {
    // Documented contract: gate transitions ALWAYS write the blob even when
    // the sync gate is OFF — boot-time discovery reads only the blob.
    // Enforced structurally by AppStore.setMetadataGate calling save() before
    // any matrix consultation; here we pin the matrix itself for the record.
    test('sync OFF does not leak into legacy-mode reads', () {
      final state = const AppState()
          .copyWith(useMetadataSettings: false, syncLegacyBlob: false);
      expect(PersistPolicy.targets(state).writeBlob, isTrue,
          reason: 'master gate is still OFF → full legacy behavior');
    });
  });

  test('new state fields roundtrip through toJson/fromJson', () {
    final state = const AppState()
        .copyWith(useMetadataSettings: true, syncLegacyBlob: false);
    // Same string round-trip normalization the store and bridge rely on
    // (nested freezed toJson values need it before fromJson).
    final restored = AppState.fromJson(
      json.decode(json.encode(state.toJson())) as Map<String, dynamic>,
    );
    expect(restored.useMetadataSettings, isTrue);
    expect(restored.syncLegacyBlob, isFalse);
    expect(restored.themeMode, ThemeMode.system); // untouched field survives
  });
}
