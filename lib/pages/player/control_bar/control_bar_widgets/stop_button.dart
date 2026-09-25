import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/features/windows/desktop_keyboard/view/shortcut_hints.dart';
import 'package:iris/pages/player/control_bar/control_bar_layout/control_bar_slot_actions.dart';
import 'package:iris/pages/player/control_bar/control_bar_widgets/control_bar_constants.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/a11y_tooltip.dart';

class StopButton extends HookWidget {
  const StopButton({
    super.key,
    required this.showControl,
    this.color,
    this.overlayColor,
  });

  final void Function() showControl;
  final Color? color;
  final WidgetStateProperty<Color?>? overlayColor;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final scheme = useEffectiveKeyboardScheme(context);

    return a11yTooltipIconButton(
      context: context,
      tooltip: '${t.stop} ( ${shortcutHintLabelFor(ShortcutHintKind.stop, scheme)} )',
      icon: Icon(Icons.stop_rounded, size: kIconSizePrimary, color: color),
      onPressed: () {
        showControl();
        // While the controls target 副音, stop halts the bg runtime AND latches
        // the gate closed (the same intent as the quick-bar gate OFF) — the
        // foreground scenario must not be advanced/stopped underneath it, and
        // its autoplay flag must stay untouched.
        // ignore: discarded_futures
        stopFromControlBar(context);
      },
      style: ButtonStyle(overlayColor: overlayColor),
    );
  }
}
