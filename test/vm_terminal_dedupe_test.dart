import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/virtual_media/playback/vm_playback_controller.dart';

/// A second terminal event (error/completed) for the SAME segment arriving
/// while the first one is still driving a transition/feed must be dropped —
/// otherwise one broken file advances two segments.
void main() {
  group('shouldDropVmTerminalEvent', () {
    test('drops duplicate for same segment while transitioning', () {
      expect(
        shouldDropVmTerminalEvent(
          handledKey: 'scope:1:key-b',
          incomingKey: 'scope:1:key-b',
          transitioning: true,
          feedInFlight: false,
        ),
        isTrue,
      );
    });

    test('drops duplicate for same segment while feed in flight', () {
      expect(
        shouldDropVmTerminalEvent(
          handledKey: 'scope:1:key-b',
          incomingKey: 'scope:1:key-b',
          transitioning: false,
          feedInFlight: true,
        ),
        isTrue,
      );
    });

    test('handles event for a new segment', () {
      expect(
        shouldDropVmTerminalEvent(
          handledKey: 'scope:1:key-b',
          incomingKey: 'scope:2:key-c',
          transitioning: true,
          feedInFlight: true,
        ),
        isFalse,
      );
    });

    test('handles event when idle (no terminal in flight)', () {
      expect(
        shouldDropVmTerminalEvent(
          handledKey: null,
          incomingKey: 'scope:0:key-a',
          transitioning: false,
          feedInFlight: false,
        ),
        isFalse,
      );
    });

    test('same segment when idle is handled (settled state)', () {
      expect(
        shouldDropVmTerminalEvent(
          handledKey: 'scope:1:key-b',
          incomingKey: 'scope:1:key-b',
          transitioning: false,
          feedInFlight: false,
        ),
        isFalse,
      );
    });
  });
}
