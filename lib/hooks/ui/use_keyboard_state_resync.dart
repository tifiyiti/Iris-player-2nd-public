import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/platform.dart';
import 'package:window_manager/window_manager.dart';

/// Drops the framework's pressed-key cache when the OS window loses focus.
///
/// A KeyUp delivered while another window owns focus never reaches the app, so
/// [HardwareKeyboard] keeps that key — typically Ctrl/Shift — "pressed" for the
/// rest of the session. The PotPlayer scheme then resolves plain Z/X/C against
/// a phantom modifier: all three are unbound (Alt+X would even quit), so the
/// speed keys silently die until the modifier is pressed again. Flutter only
/// syncs this cache once at binding init (`syncKeyboardState` never clears), so
/// we drop the stale set ourselves on blur.
///
/// Also flushes any pending live speed change (a held X/C mutates only memory
/// until KeyUp; a KeyUp swallowed by a dialog/blur would otherwise never land).
void useKeyboardStateResync() {
  useEffect(() {
    if (!isDesktop) return null;
    final listener = _KeyboardStateResyncListener();
    windowManager.addListener(listener);
    return () => windowManager.removeListener(listener);
  }, const []);
}

class _KeyboardStateResyncListener extends WindowListener {
  @override
  void onWindowBlur() {
    clearStaleKeyboardState();
    unawaited(useAppStore().commitRate());
  }
}

/// Synthesizes a KeyUp for every key the framework still believes is held.
///
/// Dispatching through [HardwareKeyboard.handleKeyEvent] clears the framework's
/// internal cache AND notifies handlers (a commitRate on a phantom X is a
/// harmless no-op), unlike the test-only `clearState()` which drops handlers.
void clearStaleKeyboardState() {
  final keyboard = HardwareKeyboard.instance;
  for (final physical in keyboard.physicalKeysPressed.toList()) {
    final logical = keyboard.lookUpLayout(physical);
    if (logical == null) continue;
    keyboard.handleKeyEvent(KeyUpEvent(
      physicalKey: physical,
      logicalKey: logical,
      timeStamp: Duration.zero,
    ));
  }
}
