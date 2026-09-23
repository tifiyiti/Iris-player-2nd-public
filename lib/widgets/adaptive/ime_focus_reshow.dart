import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/utils/platform.dart';

/// Replays `TextInput.show` whenever focus moves to a different text field.
///
/// Xiaomi HyperOS enables a "secure keyboard" for `obscureText` fields by
/// default, i.e. a different IME than the normal one. Moving focus BETWEEN a
/// password field and a normal field makes Android switch IMEs, and the first
/// `showSoftInput` issued during that switch is swallowed — the field gets
/// focus but the keyboard only appears on a SECOND tap (flutter/flutter
/// #166311). Replaying the show request after the focus has settled is exactly
/// what that second tap does, while keeping the secure keyboard (fields stay
/// `obscureText: true`).
///
/// Form-level (not per-node) so BOTH directions are covered: normal → password
/// and password → normal. There is no visibility short-circuit on purpose — at
/// the instant focus changes the OLD keyboard is usually still visible, which
/// is precisely the switch to recover from. When the keyboard is genuinely
/// ready, `showSoftInput` is a no-op.
///
/// Does ZERO per-frame work and never rebuilds a widget (focus listener + a
/// couple of short timers only).
void useImeReshowOnFocusChange() {
  useEffect(() {
    if (!isMobilePlatform) return null;
    final timers = <Timer>[];
    EditableTextState? lastState;

    EditableTextState? currentState() {
      final focusContext = FocusManager.instance.primaryFocus?.context;
      if (focusContext == null) return null;
      return focusContext.findAncestorStateOfType<EditableTextState>();
    }

    void cancelTimers() {
      for (final t in timers) {
        t.cancel();
      }
      timers.clear();
    }

    void replay(EditableTextState target) {
      // The user may have moved on before the delayed replay fired.
      if (!identical(currentState(), target)) return;
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    }

    void onFocusChange() {
      final state = currentState();
      if (state == null) {
        lastState = null;
        cancelTimers();
        return;
      }
      if (identical(state, lastState)) return;
      lastState = state;
      // The IME switch resolves within a frame or two; replay once after it
      // settles, with a late backstop for slower IMEs.
      cancelTimers();
      timers.add(Timer(const Duration(milliseconds: 150), () => replay(state)));
      timers.add(Timer(const Duration(milliseconds: 400), () => replay(state)));
    }

    FocusManager.instance.addListener(onFocusChange);
    return () {
      FocusManager.instance.removeListener(onFocusChange);
      cancelTimers();
    };
  }, const []);
}
