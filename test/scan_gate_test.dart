import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/scenario_playback/actions/scan_play_gate.dart';
import 'package:iris/l10n/app_localizations_en.dart';
import 'package:iris/l10n/app_localizations_zh.dart';

/// Pure scan-gate decision logic: state mapping + staleness window.
void main() {
  group('classifyDirScanStatus', () {
    test('notScan / scanning / error map directly', () {
      expect(
        classifyDirScanStatus(state: 'notScan', lastScanAt: null, now: DateTime(2026, 1, 1), reminderMinutes: 120),
        DirScanGateStatus.unscanned,
      );
      expect(
        classifyDirScanStatus(state: 'scanning', lastScanAt: null, now: DateTime(2026, 1, 1), reminderMinutes: 120),
        DirScanGateStatus.scanning,
      );
      expect(
        classifyDirScanStatus(state: 'error', lastScanAt: null, now: DateTime(2026, 1, 1), reminderMinutes: 120),
        DirScanGateStatus.error,
      );
    });

    test('scanDone within window passes; beyond window is stale', () {
      final now = DateTime(2026, 1, 10, 12, 0);
      final fresh = now.subtract(const Duration(minutes: 30));
      final old = now.subtract(const Duration(hours: 5));

      expect(
        classifyDirScanStatus(state: 'scanDone', lastScanAt: fresh, now: now, reminderMinutes: 120),
        DirScanGateStatus.done,
      );
      expect(
        classifyDirScanStatus(state: 'scanDone', lastScanAt: old, now: now, reminderMinutes: 120),
        DirScanGateStatus.stale,
      );
    });

    test('missing row (null state) is unscanned; null lastScanAt on scanDone is stale-safe', () {
      expect(
        classifyDirScanStatus(state: null, lastScanAt: null, now: DateTime(2026, 1, 1), reminderMinutes: 120),
        DirScanGateStatus.unscanned,
      );
      // scanDone without a timestamp: treat as fresh enough (never scanned
      // timestamps only happen on corrupt rows; don't block playback).
      expect(
        classifyDirScanStatus(state: 'scanDone', lastScanAt: null, now: DateTime(2026, 1, 1), reminderMinutes: 120),
        DirScanGateStatus.done,
      );
    });

    test('reminder window of 0 disables staleness entirely', () {
      final now = DateTime(2026, 1, 10, 12, 0);
      final ancient = now.subtract(const Duration(days: 30));
      expect(
        classifyDirScanStatus(state: 'scanDone', lastScanAt: ancient, now: now, reminderMinutes: 0),
        DirScanGateStatus.done,
      );
    });
  });

  group('resolveLiveScanStatus', () {
    test('a scanning stamp backed by a live scan stays scanning', () {
      expect(
        resolveLiveScanStatus(DirScanGateStatus.scanning, scanLive: true),
        DirScanGateStatus.scanning,
      );
    });

    test('a stale scanning stamp degrades to unscanned (so a rescan is offered)',
        () {
      // The stamp is only cleared by a successful completion of that exact
      // subtree, so a failed child listing / stopped run leaves it forever —
      // claiming "being scanned" would hide the rescan button permanently.
      expect(
        resolveLiveScanStatus(DirScanGateStatus.scanning, scanLive: false),
        DirScanGateStatus.unscanned,
      );
    });

    test('non-scanning statuses are untouched', () {
      for (final status in [
        DirScanGateStatus.done,
        DirScanGateStatus.stale,
        DirScanGateStatus.error,
        DirScanGateStatus.unscanned,
      ]) {
        expect(resolveLiveScanStatus(status, scanLive: false), status);
        expect(resolveLiveScanStatus(status, scanLive: true), status);
      }
    });
  });

  group('staleness text', () {
    test('formats hours/minutes in Chinese', () {
      final t = AppLocalizationsZh();
      expect(formatStaleness(const Duration(hours: 2, minutes: 5), t), '2小时05分');
      expect(formatStaleness(const Duration(minutes: 45), t), '45分');
      expect(formatStaleness(const Duration(hours: 30), t), '30小时');
    });

    test('formats hours/minutes in English', () {
      final t = AppLocalizationsEn();
      expect(formatStaleness(const Duration(hours: 2, minutes: 5), t), '2h 05m');
      expect(formatStaleness(const Duration(minutes: 45), t), '45m');
      expect(formatStaleness(const Duration(hours: 30), t), '30h');
    });
  });
}
