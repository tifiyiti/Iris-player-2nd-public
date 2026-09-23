import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart' show Alignment;
import 'package:iris/features/meta_settings/engine/osd_resolver.dart';
import 'package:iris/models/store/app_state.dart';

void main() {
  group('resolveOsdEnabled', () {
    test('gate OFF degrades to false regardless of stored true', () {
      const s = AppState(osdEnabled: true, useMetadataSettings: false);
      expect(resolveOsdEnabled(s, false), isFalse);
    });

    test('gate ON reflects stored value', () {
      const on = AppState(osdEnabled: true, useMetadataSettings: true);
      const off = AppState(osdEnabled: false, useMetadataSettings: true);
      expect(resolveOsdEnabled(on, true), isTrue);
      expect(resolveOsdEnabled(off, true), isFalse);
    });
  });

  group('resolveOsdShouldShow', () {
    test('disabled never shows even with always mode', () {
      const s = AppState(
        osdEnabled: false,
        osdVisibilityMode: OsdVisibilityMode.always,
        useMetadataSettings: true,
      );
      expect(resolveOsdShouldShow(s, true, isShowControl: false), isFalse);
      expect(resolveOsdShouldShow(s, true, isShowControl: true), isFalse);
    });

    test('always mode shows regardless of control visibility', () {
      const s = AppState(
        osdEnabled: true,
        osdVisibilityMode: OsdVisibilityMode.always,
        useMetadataSettings: true,
      );
      expect(resolveOsdShouldShow(s, true, isShowControl: false), isTrue);
      expect(resolveOsdShouldShow(s, true, isShowControl: true), isTrue);
    });

    test('hideWhenControlVisible suppresses while control visible', () {
      const s = AppState(
        osdEnabled: true,
        osdVisibilityMode: OsdVisibilityMode.hideWhenControlVisible,
        useMetadataSettings: true,
      );
      expect(resolveOsdShouldShow(s, true, isShowControl: false), isTrue);
      expect(resolveOsdShouldShow(s, true, isShowControl: true), isFalse);
    });
  });

  group('resolveOsdAlignment', () {
    test('9-grid maps correctly', () {
      expect(resolveOsdAlignment(OsdHAlign.left, OsdVAlign.top), Alignment.topLeft);
      expect(resolveOsdAlignment(OsdHAlign.center, OsdVAlign.middle), Alignment.center);
      expect(resolveOsdAlignment(OsdHAlign.right, OsdVAlign.bottom), Alignment.bottomRight);
      expect(resolveOsdAlignment(OsdHAlign.left, OsdVAlign.bottom), Alignment.bottomLeft);
      expect(resolveOsdAlignment(OsdHAlign.right, OsdVAlign.top), Alignment.topRight);
    });
  });
}
