import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/scenario_playback/playback/playback_progress.dart';

void main() {
  group('clampResumePosition', () {
    test('returns null when there is no saved position', () {
      expect(clampResumePosition(null, 100000), isNull);
      expect(clampResumePosition(0, 100000), isNull);
      expect(clampResumePosition(-1, 100000), isNull);
    });

    test('restores a mid-file position verbatim', () {
      expect(clampResumePosition(50000, 100000), 50000);
      expect(clampResumePosition(168633, 252052), 168633);
    });

    test('clamps positions within the last 5 seconds to the tail', () {
      expect(clampResumePosition(96000, 100000), 95000);
      expect(clampResumePosition(99967, 100000), 95000);
    });

    test('clamps positions at or beyond the duration', () {
      expect(clampResumePosition(100000, 100000), 95000);
      expect(clampResumePosition(101000, 100000), 95000);
      expect(clampResumePosition(92757, 92756), 87756);
    });

    test('clamps short clips (< 5s) back to the start', () {
      expect(clampResumePosition(3000, 2000), 0);
      expect(clampResumePosition(1000, 3000), 0);
    });

    test('keeps the position when the duration is unknown', () {
      expect(clampResumePosition(50000, 0), 50000);
      expect(clampResumePosition(50000, -1), 50000);
    });
  });

  group('resolveOpenResume (DB-authoritative open resume)', () {
    test('mid-file DB position seeks to it', () {
      final (decision, target) = resolveOpenResume(106510, 209553, 0);
      expect(decision, OpenResumeDecision.seekDb);
      expect(target, 106510);
    });

    test('DB row cleared to 0 with no budget starts from the beginning', () {
      final (decision, target) = resolveOpenResume(0, 209553, 0);
      expect(decision, OpenResumeDecision.fromBeginningExplicit);
      expect(target, 0);
    });

    test('DB row at 0 with restore budget falls back to history', () {
      final (decision, target) = resolveOpenResume(0, 209553, 2);
      expect(decision, OpenResumeDecision.fallbackHistory);
      expect(target, 0);
    });

    test('negative DB position with budget falls back to history', () {
      final (decision, target) = resolveOpenResume(-5, 100000, 1);
      expect(decision, OpenResumeDecision.fallbackHistory);
      expect(target, 0);
    });

    test('no DB row falls back to HistoryStore', () {
      final (decision, target) = resolveOpenResume(null, 209553, 0);
      expect(decision, OpenResumeDecision.fallbackHistory);
      expect(target, 0);
    });

    test('DB position within the tail window clamps to the tail', () {
      final (decision, target) = resolveOpenResume(208000, 209553, 0);
      expect(decision, OpenResumeDecision.seekDb);
      expect(target, 209553 - resumeEndSafetyMs);
    });
  });
}
