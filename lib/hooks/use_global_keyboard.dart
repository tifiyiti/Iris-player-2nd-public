import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// Whether global player key dispatch may act for [context] right now.
///
/// Two guards, both guarding against the global intake (which sees EVERY key
/// event app-wide) hijacking keys that belong to other UI:
/// 1. The enclosing modal route must be current — when a dialog / popup route
///    sits on top it handles its own keys (e.g. its own Esc close listener).
/// 2. The primary focus must not live inside a text field — typing in the
///    dock search box, dialogs or editors must never trigger player
///    shortcuts (Esc included: fields keep their native behavior).
bool playerKeysAllowed(BuildContext context) {
  // The global HardwareKeyboard intake sees EVERY key event app-wide, and its
  // handler outlives a frame that is tearing this element down (or one whose
  // tree was just invalidated by a layout assert). Looking up an ancestor from
  // a deactivated element throws "Looking up a deactivated widget's ancestor is
  // unsafe" — a second, unrelated exception stacked on the real one. Refuse to
  // act instead of querying the inherited tree.
  if (!context.mounted) return false;
  final ModalRoute<dynamic>? route = ModalRoute.of(context);
  if (route != null && !route.isCurrent) return false;
  final BuildContext? focusContext =
      FocusManager.instance.primaryFocus?.context;
  if (focusContext == null) return true;
  return focusContext.findAncestorStateOfType<EditableTextState>() == null;
}

/// Registers [onKeyEvent] on the GLOBAL [HardwareKeyboard] pipeline.
///
/// Why global: the player page previously received keys through a
/// widget-scoped `KeyboardListener` whose focus node went deaf the moment
/// primary focus moved into a sibling subtree (e.g. the docked playlist
/// panel) — every shortcut silently died until something happened to
/// re-request focus. HardwareKeyboard handlers see every key event
/// regardless of focus; the handler itself decides relevance via
/// [playerKeysAllowed].
///
/// The dispatch closure is kept fresh across rebuilds via a ref, and events
/// are never consumed (always reports unhandled) so focus traversal, IME and
/// other listeners keep working unchanged.
void useGlobalKeyboard(void Function(KeyEvent event) onKeyEvent) {
  final latest = useRef(onKeyEvent);
  latest.value = onKeyEvent;
  useEffect(() {
    // Never consume: false lets focus traversal / IME / other listeners
    // process the event exactly as they did before.
    bool dispatch(KeyEvent event) {
      latest.value(event);
      return false;
    }

    HardwareKeyboard.instance.addHandler(dispatch);
    return () => HardwareKeyboard.instance.removeHandler(dispatch);
  }, const []);
}
