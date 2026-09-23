import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/engine/background_scope_logic.dart';

void main() {
  group('shouldStopStaleEngine (P1-7)', () {
    test('stops only when enabled with no file to play', () {
      expect(
        shouldStopStaleEngine(enabled: true, hasOpenTarget: false),
        isTrue,
        reason: 'enabled + empty/OOB queue must not keep the old audio',
      );
      expect(shouldStopStaleEngine(enabled: true, hasOpenTarget: true),
          isFalse);
      expect(shouldStopStaleEngine(enabled: false, hasOpenTarget: false),
          isFalse,
          reason: 'the disabled path already has its own stop effect');
      expect(shouldStopStaleEngine(enabled: false, hasOpenTarget: true),
          isFalse);
    });
  });
}
