import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/windows/desktop_keyboard/view/shortcut_hints.dart';
import 'package:iris/pages/player/control_bar/control_bar_widgets/control_bar_constants.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/a11y_tooltip.dart';

class FullscreenButton extends HookWidget {
  const FullscreenButton({
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
    final isFullScreen = usePlayerUiStore().select(context, (s) => s.isFullScreen);
    final scheme = useEffectiveKeyboardScheme(context);
    final hint = shortcutHintLabelFor(ShortcutHintKind.fullscreen, scheme);

    return a11yTooltipIconButton(
      context: context,
      tooltip: isFullScreen ? '${t.exit_fullscreen} ( $hint )' : '${t.enter_fullscreen} ( $hint )',
      icon: Icon(
        isFullScreen ? Icons.close_fullscreen_rounded : Icons.open_in_full_rounded,
        size: kFullscreenIconSize,
        color: color,
      ),
      onPressed: () {
        showControl();
        usePlayerUiStore().updateFullScreen(!isFullScreen);
      },
      style: ButtonStyle(overlayColor: overlayColor),
    );
  }
}
