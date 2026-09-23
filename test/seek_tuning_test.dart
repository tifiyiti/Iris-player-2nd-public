import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/meta_settings/contributions/settings_catalog.dart';
import 'package:iris/features/meta_settings/engine/video_cache_preset.dart';
import 'package:iris/hooks/player/seek_tuning.dart';
import 'package:iris/models/enums/video_cache_preset.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/utils/live_seek_throttle.dart';

void main() {
  group('resolveRelativeBaseMs', () {
    test('uses the reported position when no intent is armed', () {
      expect(
        resolveRelativeBaseMs(reportedMs: 1000, pendingIntentMs: null),
        1000,
      );
    });

    test('accumulates onto the armed intent while a seek is in flight', () {
      expect(
        resolveRelativeBaseMs(reportedMs: 1000, pendingIntentMs: 5000),
        5000,
      );
    });
  });

  group('StepIntent', () {
    const int step = 4000;

    test('falls back to the reported position while nothing is recorded', () {
      expect(
        StepIntent().baseFor(reportedMs: 1000, lockIntentMs: null),
        1000,
      );
    });

    test('prefers the step intent over the position-lock intent', () {
      // The lock unlocks on the first ±2s landing sample (isLandingAt), so
      // during a rapid burst its target is often already gone; the step
      // intent must keep accumulating regardless.
      final i = StepIntent()..note(5000);
      expect(i.baseFor(reportedMs: 1000, lockIntentMs: 5000), 5000);
      expect(i.baseFor(reportedMs: 1000, lockIntentMs: null), 5000);
    });

    test('keeps the lock intent when no step has been recorded yet', () {
      expect(
        StepIntent().baseFor(reportedMs: 1000, lockIntentMs: 7000),
        7000,
      );
    });

    test('N presses advance exactly N steps while the reported position '
        'sits still (hr-seek=no keyframe snap-back)', () {
      final i = StepIntent();
      // 60fps file, keyint=250 → ~4.17s GOP: every 4s step lands on the SAME
      // keyframe, so the engine reports an unmoved position on every repeat.
      const int reported = 541233;
      int target = reported;
      for (int press = 1; press <= 5; press++) {
        target = i.baseFor(reportedMs: reported, lockIntentMs: null) + step;
        i.note(target);
        expect(target, reported + step * press, reason: 'press $press');
      }
    });

    test('a lock that unlocks mid-burst does not rewind the accumulation', () {
      final i = StepIntent()..note(489583);
      // Lock already unlocked (landing tolerance fired) and the engine is
      // still sitting on the previous keyframe.
      expect(i.baseFor(reportedMs: 485566, lockIntentMs: null) + step, 493583);
      i.note(493583);
      expect(i.baseFor(reportedMs: 485583, lockIntentMs: null) + step, 497583);
    });

    test('reset drops the accumulation so an absolute seek restarts it', () {
      final i = StepIntent()..note(9000);
      i.reset();
      expect(i.lastMs, isNull);
      expect(i.baseFor(reportedMs: 1200, lockIntentMs: null), 1200);
    });

    test('note replaces the previous target', () {
      final i = StepIntent()..note(9000)..note(13000);
      expect(i.lastMs, 13000);
    });
  });

  group('StepBurst', () {
    test('a lone press never counts as rapid', () {
      final b = StepBurst(window: const Duration(milliseconds: 400));
      final DateTime t0 = DateTime(2026);
      expect(b.note(t0), isFalse);
      expect(b.isRapid, isFalse);
    });

    test('a second press inside the window makes the burst rapid', () {
      final b = StepBurst(window: const Duration(milliseconds: 400));
      final DateTime t0 = DateTime(2026);
      b.note(t0);
      expect(b.note(t0.add(const Duration(milliseconds: 120))), isTrue);
      expect(b.isRapid, isTrue);
    });

    test('a slow follow-up press stays on the exact path', () {
      final b = StepBurst(window: const Duration(milliseconds: 400));
      final DateTime t0 = DateTime(2026);
      b.note(t0);
      expect(b.note(t0.add(const Duration(milliseconds: 900))), isFalse);
    });

    test('reset clears the burst so the next press is a fresh start', () {
      final b = StepBurst(window: const Duration(milliseconds: 400));
      final DateTime t0 = DateTime(2026);
      b.note(t0);
      b.note(t0.add(const Duration(milliseconds: 50)));
      expect(b.isRapid, isTrue);
      b.reset();
      expect(b.isRapid, isFalse);
      expect(b.note(t0.add(const Duration(milliseconds: 60))), isFalse);
    });
  });

  group('TrailingCoalescer', () {
    test('keeps only the newest value and clears on flush', () {
      final c = TrailingCoalescer<int>();
      expect(c.hasPending, isFalse);
      c.record(1);
      expect(c.hasPending, isTrue);
      c.record(2);
      expect(c.flush(), 2);
      expect(c.hasPending, isFalse);
      expect(c.flush(), isNull);
    });
  });

  group('LiveSeekThrottle', () {
    test('allows one seek per interval and re-arms on reset', () {
      final t = LiveSeekThrottle(minInterval: const Duration(milliseconds: 120));
      final DateTime t0 = DateTime(2026);
      expect(t.allow(t0), isTrue);
      expect(t.allow(t0.add(const Duration(milliseconds: 60))), isFalse);
      expect(t.allow(t0.add(const Duration(milliseconds: 130))), isTrue);
      t.reset();
      expect(t.allow(t0.add(const Duration(milliseconds: 140))), isTrue);
    });
  });

  group('VideoCachePreset', () {
    test('every preset keeps the backward cache within the forward one', () {
      for (final VideoCachePreset p in VideoCachePreset.values) {
        expect(p.backBytes <= p.maxBytes, isTrue, reason: '$p');
        expect(p.backBytes, greaterThan(0));
      }
    });

    test('presets grow monotonically and balanced is the tuned default', () {
      expect(
        VideoCachePreset.low.maxBytes < VideoCachePreset.balanced.maxBytes,
        isTrue,
      );
      expect(
        VideoCachePreset.balanced.maxBytes < VideoCachePreset.high.maxBytes,
        isTrue,
      );
      // balanced == the values the media_kit hook asserts by default.
      expect(VideoCachePreset.balanced.maxBytes, 150 * 1024 * 1024);
      expect(VideoCachePreset.balanced.backBytes, 64 * 1024 * 1024);
    });
  });

  group('resolveVideoCachePreset', () {
    test('returns the stored preset while the metadata gate is ON', () {
      const AppState s = AppState(videoCachePreset: VideoCachePreset.high);
      expect(
        resolveVideoCachePreset(s, metadataEnabled: true),
        VideoCachePreset.high,
      );
    });

    test('degrades to balanced while the gate is OFF', () {
      const AppState s = AppState(videoCachePreset: VideoCachePreset.high);
      expect(
        resolveVideoCachePreset(s, metadataEnabled: false),
        VideoCachePreset.balanced,
      );
    });
  });

  group('playback.videoCachePreset catalog def', () {
    final def = SettingsCatalog.defs
        .singleWhere((d) => d.key == 'playback.videoCachePreset');

    test('enum values mirror the Dart enum names', () {
      expect(def.enumValues, VideoCachePreset.values.map((v) => v.name).toList());
    });

    test('default is the balanced preset', () {
      expect(def.defaultValue, VideoCachePreset.balanced.name);
    });

    test('is a custom row (out-of-domain AUX) with an editor key', () {
      expect(def.editorKey, isNotNull);
    });
  });
}
