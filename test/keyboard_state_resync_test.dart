import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/hooks/ui/use_keyboard_state_resync.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final keyboard = HardwareKeyboard.instance;

  setUp(() => keyboard.clearState());
  tearDown(() => keyboard.clearState());

  test('drops a stuck modifier left by a lost KeyUp', () {
    // Simulate Ctrl held with no KeyUp ever arriving (window lost focus).
    keyboard.handleKeyEvent(KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.controlLeft,
      logicalKey: LogicalKeyboardKey.controlLeft,
      timeStamp: Duration.zero,
    ));
    expect(keyboard.isControlPressed, isTrue);

    clearStaleKeyboardState();

    expect(keyboard.isControlPressed, isFalse);
    expect(keyboard.logicalKeysPressed, isEmpty);
  });

  test('drops every stale key, including a real key plus modifier', () {
    for (final pair in <(PhysicalKeyboardKey, LogicalKeyboardKey)>[
      (PhysicalKeyboardKey.controlLeft, LogicalKeyboardKey.controlLeft),
      (PhysicalKeyboardKey.keyX, LogicalKeyboardKey.keyX),
    ]) {
      keyboard.handleKeyEvent(KeyDownEvent(
        physicalKey: pair.$1,
        logicalKey: pair.$2,
        timeStamp: Duration.zero,
      ));
    }
    expect(keyboard.logicalKeysPressed, isNotEmpty);

    clearStaleKeyboardState();

    expect(keyboard.logicalKeysPressed, isEmpty);
  });

  test('is a no-op when nothing is pressed', () {
    expect(keyboard.logicalKeysPressed, isEmpty);
    clearStaleKeyboardState();
    expect(keyboard.logicalKeysPressed, isEmpty);
  });
}
