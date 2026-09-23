import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/widgets/controls/vertical_value_strip.dart';
import 'package:popover/popover.dart';

/// Seek-step adjuster — anchored popover, transparent background, only the
/// top value + the vertical strip are visible.
///
/// Moved out of the control bar (sub_media §3): the setting is reached from the
/// More menu now, so this file only owns the popover, not a button.
Future<void> showSeekStepPopover(BuildContext context) => showPopover(
      context: context,
      bodyBuilder: (context) => const Material(
        type: MaterialType.transparency,
        child: _SeekStepPopoverContent(),
      ),
      direction: PopoverDirection.top,
      width: 56,
      height: 220,
      arrowHeight: 0,
      arrowWidth: 0,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
    );

/// Back-compat alias.
Future<void> showSeekStepDialog(BuildContext context) =>
    showSeekStepPopover(context);

class _SeekStepPopoverContent extends HookWidget {
  const _SeekStepPopoverContent();

  @override
  Widget build(BuildContext context) {
    final int sec = useAppStore().select(context, (s) => s.seekStepSeconds);

    // Live changes never touch storage while adjusting (a held key repeats at
    // ~30×/s); persist once when the popover closes, whatever the close path
    // (barrier tap / Esc / programmatic).
    useEffect(() {
      return () {
        useAppStore().commitSeekStepSeconds();
      };
    }, const []);

    // Keyboard adjust (Ctrl+↑/↓ opens this popover): ↑/↓ move the base step by
    // 1s, Shift+↑/↓ by 10s, applied live; KeyUp commits. The popover is a
    // root-navigator modal route, so the player's global shortcut handler is
    // gated off while it is open — these arrows cannot leak into a seek.
    KeyEventResult onKey(FocusNode node, KeyEvent event) {
      final LogicalKeyboardKey key = event.logicalKey;
      if (key != LogicalKeyboardKey.arrowUp &&
          key != LogicalKeyboardKey.arrowDown) {
        return KeyEventResult.ignored;
      }
      final store = useAppStore();
      if (event is KeyUpEvent) {
        store.commitSeekStepSeconds();
        return KeyEventResult.handled;
      }
      final int magnitude = HardwareKeyboard.instance.isShiftPressed ? 10 : 1;
      final int delta =
          key == LogicalKeyboardKey.arrowUp ? magnitude : -magnitude;
      store.updateSeekStepSecondsLive(store.state.seekStepSeconds + delta);
      return KeyEventResult.handled;
    }

    return Focus(
      autofocus: true,
      onKeyEvent: onKey,
      child: Container(
        // No card — pure transparent container, only the two children are visible.
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${sec}s',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    shadows: const [
                      Shadow(blurRadius: 4, color: Colors.black54),
                    ],
                  ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: VerticalValueStrip(
                value: sec,
                min: 1,
                max: 120,
                stripWidth: 36,
                onChangeEnd: (_) => useAppStore().commitSeekStepSeconds(),
                onChanged: (v) => useAppStore().updateSeekStepSecondsLive(v),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
