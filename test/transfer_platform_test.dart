import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/settings_transfer/engine/platform_key_policy.dart';
import 'package:iris/features/settings_transfer/model/export_envelope.dart';

// Cross-platform transfer policy: same-platform migrates everything,
// cross-platform (desktop <-> mobile) keeps common + target-platform keys
// and skips source-platform-only keys (notably WebDAV/FTP storages always
// migrate — they are the primary limited-interop scenario).
void main() {
  group('transferPlatformName', () {
    test('maps every TargetPlatform to the settings-transfer id', () {
      expect(transferPlatformName(TargetPlatform.android), 'android');
      expect(transferPlatformName(TargetPlatform.iOS), 'ios');
      expect(transferPlatformName(TargetPlatform.windows), 'windows');
      expect(transferPlatformName(TargetPlatform.linux), 'linux');
      expect(transferPlatformName(TargetPlatform.macOS), 'macos');
    });
  });

  group('PlatformKeyPolicy snapshot fields', () {
    test('desktop file -> android keeps common, skips desktop-only', () {
      const snapshot = <String, dynamic>{
        'language': 'zh',
        'volume': 80,
        'autoResize': true,
        'keyboardShortcutScheme': 'potplayer',
        'desktopControlBarLayout': 'stacked',
        'preferredOrientation': 'landscape',
        'gestureMode': 'classic',
      };
      final kept = snapshot.keys
          .where((k) => PlatformKeyPolicy.isTransferableSnapshotField(k, 'android'))
          .toSet();
      expect(kept, containsAll(['language', 'volume', 'preferredOrientation', 'gestureMode']));
      expect(kept, isNot(contains('autoResize')));
      expect(kept, isNot(contains('keyboardShortcutScheme')));
      expect(kept, isNot(contains('desktopControlBarLayout')));
    });

    test('android file -> windows keeps common, skips mobile-only', () {
      const snapshot = <String, dynamic>{
        'language': 'en',
        'autoResize': true,
        'preferredOrientation': 'landscape',
        'gestureMode': 'classic',
        'controlsTitleConfig': {'x': 1},
        'defaultPopupDirection': 'right',
        'breadcrumbStartPortrait': 'left',
      };
      final kept = snapshot.keys
          .where((k) => PlatformKeyPolicy.isTransferableSnapshotField(k, 'windows'))
          .toSet();
      expect(kept, containsAll(['language', 'autoResize']));
      expect(kept, isNot(contains('preferredOrientation')));
      expect(kept, isNot(contains('gestureMode')));
      expect(kept, isNot(contains('controlsTitleConfig')));
      expect(kept, isNot(contains('defaultPopupDirection')));
      expect(kept, isNot(contains('breadcrumbStartPortrait')));
    });

    test('same platform keeps everything', () {
      expect(PlatformKeyPolicy.isTransferableSnapshotField('autoResize', 'windows'), isTrue);
      expect(PlatformKeyPolicy.isTransferableSnapshotField('gestureMode', 'android'), isTrue);
      expect(PlatformKeyPolicy.isTransferableSnapshotField('language', 'windows'), isTrue);
    });

    test('unknown platform keeps everything (legacy files without stamp)', () {
      expect(PlatformKeyPolicy.isTransferableSnapshotField('autoResize', 'unknown'), isTrue);
      expect(PlatformKeyPolicy.isTransferableSnapshotField('gestureMode', 'unknown'), isTrue);
    });
  });

  group('PlatformKeyPolicy AUX rows', () {
    test('desktop AUX rows skipped on android, generic rows kept', () {
      expect(PlatformKeyPolicy.isTransferableAuxKey('window.fitMode', 'android'), isFalse);
      expect(PlatformKeyPolicy.isTransferableAuxKey('keybind.overrides', 'android'), isFalse);
      expect(PlatformKeyPolicy.isTransferableAuxKey('osd.enabled', 'android'), isFalse);
      expect(PlatformKeyPolicy.isTransferableAuxKey('video.desktopDisplayMode', 'android'), isFalse);
      expect(PlatformKeyPolicy.isTransferableAuxKey('screenshot.desktopDir', 'android'), isFalse);
      expect(PlatformKeyPolicy.isTransferableAuxKey('screenshot.mobileDir', 'android'), isTrue);
      expect(PlatformKeyPolicy.isTransferableAuxKey('dialring.palette', 'android'), isTrue);
      expect(PlatformKeyPolicy.isTransferableAuxKey('browse.mediaScope', 'android'), isTrue);
      expect(PlatformKeyPolicy.isTransferableAuxKey('playback.resumeOnStartup', 'android'), isTrue);
      expect(PlatformKeyPolicy.isTransferableAuxKey('slider.phonePosH', 'android'), isTrue);
      expect(PlatformKeyPolicy.isTransferableAuxKey('video.mobileDisplayMode', 'android'), isTrue);
    });

    test('mobile AUX rows skipped on windows, generic rows kept', () {
      expect(PlatformKeyPolicy.isTransferableAuxKey('video.mobileDisplayMode', 'windows'), isFalse);
      expect(PlatformKeyPolicy.isTransferableAuxKey('screenshot.mobileDir', 'windows'), isFalse);
      expect(PlatformKeyPolicy.isTransferableAuxKey('screenshot.desktopDir', 'windows'), isTrue);
      expect(PlatformKeyPolicy.isTransferableAuxKey('window.fitMode', 'windows'), isTrue);
      expect(PlatformKeyPolicy.isTransferableAuxKey('osd.enabled', 'windows'), isTrue);
      expect(PlatformKeyPolicy.isTransferableAuxKey('dialring.palette', 'windows'), isTrue);
      expect(PlatformKeyPolicy.isTransferableAuxKey('speed.mode', 'windows'), isTrue);
      expect(PlatformKeyPolicy.isTransferableAuxKey('virtualmedia.strategy', 'windows'), isTrue);
    });

    test('skip note is stable for the import report', () {
      expect(PlatformKeyPolicy.skipNoteFor('window.fitMode', 'android', isAuxRow: true), kPlatformSkippedNote);
      expect(PlatformKeyPolicy.skipNoteFor('autoResize', 'android'), kPlatformSkippedNote);
      expect(PlatformKeyPolicy.skipNoteFor('language', 'android'), isNull);
    });
  });

  group('ExportEnvelope sourcePlatform', () {
    test('create stamps current platform and roundtrip preserves it', () async {
      final env = await ExportEnvelope.create({
        'appSettings': {'subVersion': 1},
      });
      expect(env.sourcePlatform, isNotEmpty);
      expect(env.sourcePlatform, isNot('unknown'));
      final back = ExportEnvelope.decode(env.encode());
      expect(back.sourcePlatform, env.sourcePlatform);
      expect(back.sections, contains('appSettings'));
    });

    test('payload without stamp decodes as unknown (legacy files)', () {
      const raw = '{"format":2,"appVersion":"x","exportedAt":"t","sections":{}}';
      expect(ExportEnvelope.decode(raw).sourcePlatform, 'unknown');
    });
  });
}
