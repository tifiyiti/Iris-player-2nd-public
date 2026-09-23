import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/windows/desktop_keyboard/view/shortcut_hints.dart';
import 'package:iris/models/store/app_state.dart';

/// More-menu trailing hints must reflect the ACTIVE scheme (D10) — stale
/// legacy labels under potplayer would contradict the live bindings.
void main() {
  test('legacy labels match the historical hardcoded strings', () {
    expect(
      shortcutHintLabel(DesktopShortcutHintTarget.openFile,
          KeyboardShortcutScheme.legacy),
      'Ctrl + O',
    );
    expect(
      shortcutHintLabel(DesktopShortcutHintTarget.openLink,
          KeyboardShortcutScheme.legacy),
      'Ctrl + L',
    );
    expect(
      shortcutHintLabel(DesktopShortcutHintTarget.history,
          KeyboardShortcutScheme.legacy),
      'Ctrl + H',
    );
    expect(
      shortcutHintLabel(DesktopShortcutHintTarget.settings,
          KeyboardShortcutScheme.legacy),
      'Ctrl + P',
    );
    expect(
      shortcutHintLabel(
          DesktopShortcutHintTarget.exit, KeyboardShortcutScheme.legacy),
      'Alt + X',
    );
  });

  test('potplayer labels follow the new bindings', () {
    expect(
      shortcutHintLabel(DesktopShortcutHintTarget.openLink,
          KeyboardShortcutScheme.potplayer),
      'Ctrl + U',
    );
    expect(
      shortcutHintLabel(DesktopShortcutHintTarget.history,
          KeyboardShortcutScheme.potplayer),
      '; H',
    );
    expect(
      shortcutHintLabel(DesktopShortcutHintTarget.settings,
          KeyboardShortcutScheme.potplayer),
      'F5',
    );
  });

  test('identical-across-scheme targets keep one label', () {
    for (final scheme in KeyboardShortcutScheme.values) {
      expect(
        shortcutHintLabel(DesktopShortcutHintTarget.openFile, scheme),
        'Ctrl + O',
      );
      expect(
        shortcutHintLabel(DesktopShortcutHintTarget.exit, scheme),
        'Alt + X',
      );
    }
  });

  test('jump-to-time has a hint only under potplayer (no legacy binding)',
      () {
    expect(
      shortcutHintLabel(DesktopShortcutHintTarget.jumpToTime,
          KeyboardShortcutScheme.legacy),
      isNull,
    );
    expect(
      shortcutHintLabel(DesktopShortcutHintTarget.jumpToTime,
          KeyboardShortcutScheme.potplayer),
      'G',
    );
  });
}
