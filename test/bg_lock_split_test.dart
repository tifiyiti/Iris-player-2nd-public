import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/model/enum/bg_seek_link.dart';
import 'package:iris/features/background_playback/model/enum/control_target.dart';
import 'package:iris/features/background_playback/services/background_sync_logic.dart';

/// The old single-value 进度锁定 was split into two orthogonal axes:
///   seekLink  { linked, independent }
///   lockLevel { high, low }        (inert while independent)
///
/// This pins the cold-migration mapping so an upgrade cannot silently lose the
/// user's stored preference.
void main() {
  group('migrateLegacyProgressLock', () {
    test('full → linked + high', () {
      final m = migrateLegacyProgressLock('full');
      expect(m, isNotNull);
      expect(m!.link, BgSeekLink.linked);
      expect(m.level, BgLockLevel.high);
    });

    test('playPauseOnly → linked + low', () {
      final m = migrateLegacyProgressLock('playPauseOnly');
      expect(m, isNotNull);
      expect(m!.link, BgSeekLink.linked);
      expect(m.level, BgLockLevel.low);
    });

    test('independent → independent (level stays the default high)', () {
      final m = migrateLegacyProgressLock('independent');
      expect(m, isNotNull);
      expect(m!.link, BgSeekLink.independent);
      expect(m.level, BgLockLevel.high);
    });

    test('unknown/absent legacy value migrates to nothing', () {
      expect(migrateLegacyProgressLock(null), isNull);
      expect(migrateLegacyProgressLock('bogus'), isNull);
    });
  });

  group('mirrorSourceIsBackground', () {
    test('the panel target decides the master', () {
      expect(
        mirrorSourceIsBackground(
          bgEnabled: true,
          target: ControlTarget.background,
        ),
        isTrue,
      );
      expect(
        mirrorSourceIsBackground(
          bgEnabled: true,
          target: ControlTarget.foreground,
        ),
        isFalse,
      );
    });

    test('副音 cannot be the master while the subsystem is off', () {
      expect(
        mirrorSourceIsBackground(
          bgEnabled: false,
          target: ControlTarget.background,
        ),
        isFalse,
      );
    });
  });

  group('the split axes drive transport/seek independently', () {
    test('independent silences both transport and seek', () {
      expect(shouldSyncTransport(BgSeekLink.independent), isFalse);
      expect(
        shouldSyncPosition(
            link: BgSeekLink.independent, level: BgLockLevel.high),
        isFalse,
      );
    });

    test('low keeps play/pause but frees seeks', () {
      expect(shouldSyncTransport(BgSeekLink.linked), isTrue);
      expect(
        shouldSyncPosition(link: BgSeekLink.linked, level: BgLockLevel.low),
        isFalse,
      );
    });

    test('high mirrors both', () {
      expect(shouldSyncTransport(BgSeekLink.linked), isTrue);
      expect(
        shouldSyncPosition(link: BgSeekLink.linked, level: BgLockLevel.high),
        isTrue,
      );
    });
  });
}
