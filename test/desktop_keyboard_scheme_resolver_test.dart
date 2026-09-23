import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/windows/desktop_keyboard/controller/resolve_keyboard_scheme.dart';
import 'package:iris/models/store/app_state.dart';

/// Degradation contract for the desktop keyboard scheme.
///
/// Mirrors resolveScrubberSlot: while the metadata gate is OFF a stale
/// potplayer selection must degrade to the legacy bindings instead of
/// leaking new behavior to legacy-blob users.
void main() {
  group('resolveKeyboardScheme', () {
    test('gate OFF forces legacy regardless of stored value', () {
      expect(
        resolveKeyboardScheme(
          stored: KeyboardShortcutScheme.potplayer,
          metadataEnabled: false,
        ),
        KeyboardShortcutScheme.legacy,
      );
      expect(
        resolveKeyboardScheme(
          stored: KeyboardShortcutScheme.legacy,
          metadataEnabled: false,
        ),
        KeyboardShortcutScheme.legacy,
      );
    });

    test('gate ON honors the stored scheme', () {
      expect(
        resolveKeyboardScheme(
          stored: KeyboardShortcutScheme.potplayer,
          metadataEnabled: true,
        ),
        KeyboardShortcutScheme.potplayer,
      );
      expect(
        resolveKeyboardScheme(
          stored: KeyboardShortcutScheme.legacy,
          metadataEnabled: true,
        ),
        KeyboardShortcutScheme.legacy,
      );
    });
  });
}
