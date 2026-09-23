import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/scan/model/recursive_scan_state.dart';
import 'package:iris/features/meta_settings/bridge/scan_state_bridge.dart';

void main() {
  group('ScanStateBridge', () {
    test('encode → apply roundtrips the preference', () {
      const state = RecursiveScanState(autoCloseDelay: 7.5);
      final restored = ScanStateBridge.apply(
        ScanStateBridge.encodeRow(state),
        const RecursiveScanState(), // default 2.5
      );
      expect(restored.autoCloseDelay, 7.5);
    });

    test('missing row keeps base value', () {
      final restored = ScanStateBridge.apply({}, const RecursiveScanState());
      expect(restored.autoCloseDelay, 2.5);
    });

    test('malformed row is contained, never throws', () {
      final restored = ScanStateBridge.apply(
        {ScanStateBridge.key: '{broken'},
        const RecursiveScanState(),
      );
      expect(restored.autoCloseDelay, 2.5);
    });

    test('only the preference is representable — runtime fields never leak',
        () {
      final noisy = const RecursiveScanState(
        autoCloseDelay: 4.0,
        phase: ScanPhase.scanning,
        storageId: 's1',
        depthPaths: {0: ['C:/x']},
        progress: 0.42,
        totalDirs: 9,
        scannedDirs: 3,
        currentScanningPath: 'C:/x/y',
        error: null,
        paused: true,
      );
      expect(ScanStateBridge.encodeRow(noisy).keys.single,
          ScanStateBridge.key);
    });
  });
}
