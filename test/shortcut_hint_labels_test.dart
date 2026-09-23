import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/windows/desktop_keyboard/view/shortcut_hints.dart';
import 'package:iris/models/store/app_state.dart';

void main() {
  group('shortcutHintLabelFor', () {
    test('legacy scheme keeps the original control-bar hints', () {
      expect(
        shortcutHintLabelFor(ShortcutHintKind.playPause, KeyboardShortcutScheme.legacy),
        'Space',
      );
      expect(
        shortcutHintLabelFor(ShortcutHintKind.stop, KeyboardShortcutScheme.legacy),
        'Ctrl + C',
      );
      expect(
        shortcutHintLabelFor(ShortcutHintKind.previous, KeyboardShortcutScheme.legacy),
        'Ctrl + ←',
      );
      expect(
        shortcutHintLabelFor(ShortcutHintKind.next, KeyboardShortcutScheme.legacy),
        'Ctrl + →',
      );
      expect(
        shortcutHintLabelFor(ShortcutHintKind.shuffle, KeyboardShortcutScheme.legacy),
        'Ctrl + X',
      );
      expect(
        shortcutHintLabelFor(ShortcutHintKind.repeat, KeyboardShortcutScheme.legacy),
        'Ctrl + R',
      );
      expect(
        shortcutHintLabelFor(ShortcutHintKind.fit, KeyboardShortcutScheme.legacy),
        'Ctrl + V',
      );
      expect(
        shortcutHintLabelFor(ShortcutHintKind.subtitleAudio, KeyboardShortcutScheme.legacy),
        'S',
      );
      expect(
        shortcutHintLabelFor(ShortcutHintKind.playQueue, KeyboardShortcutScheme.legacy),
        'P',
      );
      expect(
        shortcutHintLabelFor(ShortcutHintKind.storage, KeyboardShortcutScheme.legacy),
        'F',
      );
      expect(
        shortcutHintLabelFor(ShortcutHintKind.mute, KeyboardShortcutScheme.legacy),
        'Ctrl + M',
      );
      expect(
        shortcutHintLabelFor(ShortcutHintKind.fullscreen, KeyboardShortcutScheme.legacy),
        'F11, Enter, Esc',
      );
      expect(
        shortcutHintLabelFor(ShortcutHintKind.alwaysOnTop, KeyboardShortcutScheme.legacy),
        'F10',
      );
    });

    test('potplayer scheme matches the live potplayer bindings (P-key fix)', () {
      expect(
        shortcutHintLabelFor(ShortcutHintKind.playPause, KeyboardShortcutScheme.potplayer),
        'Space',
      );
      expect(
        shortcutHintLabelFor(ShortcutHintKind.stop, KeyboardShortcutScheme.potplayer),
        'F4',
      );
      expect(
        shortcutHintLabelFor(ShortcutHintKind.previous, KeyboardShortcutScheme.potplayer),
        'PageUp',
      );
      expect(
        shortcutHintLabelFor(ShortcutHintKind.next, KeyboardShortcutScheme.potplayer),
        'PageDown',
      );
      expect(
        shortcutHintLabelFor(ShortcutHintKind.shuffle, KeyboardShortcutScheme.potplayer),
        '; X',
      );
      expect(
        shortcutHintLabelFor(ShortcutHintKind.repeat, KeyboardShortcutScheme.potplayer),
        '; R',
      );
      expect(
        shortcutHintLabelFor(ShortcutHintKind.fit, KeyboardShortcutScheme.potplayer),
        'J',
      );
      expect(
        shortcutHintLabelFor(ShortcutHintKind.subtitleAudio, KeyboardShortcutScheme.potplayer),
        'A / L',
      );
      expect(
        shortcutHintLabelFor(ShortcutHintKind.playQueue, KeyboardShortcutScheme.potplayer),
        'F6',
      );
      expect(
        shortcutHintLabelFor(ShortcutHintKind.storage, KeyboardShortcutScheme.potplayer),
        '; F',
      );
      expect(
        shortcutHintLabelFor(ShortcutHintKind.mute, KeyboardShortcutScheme.potplayer),
        'M',
      );
      expect(
        shortcutHintLabelFor(ShortcutHintKind.fullscreen, KeyboardShortcutScheme.potplayer),
        'Enter / Esc',
      );
      expect(
        shortcutHintLabelFor(ShortcutHintKind.alwaysOnTop, KeyboardShortcutScheme.potplayer),
        'Ctrl + T',
      );
    });
  });
}