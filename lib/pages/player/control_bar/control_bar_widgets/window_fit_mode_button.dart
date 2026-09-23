import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/osd/engine/osd_texts.dart';
import 'package:iris/features/osd/engine/show_player_osd.dart';
import 'package:iris/features/windows/desktop_keyboard/view/shortcut_hints.dart';
import 'package:iris/models/store/window_fit_mode.dart';
import 'package:iris/pages/player/control_bar/control_bar_widgets/control_bar_constants.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/a11y_tooltip.dart';

/// Desktop control-bar toggle for the 窗口适应模式 (WindowsPotPlayer parity):
/// [WindowFitMode.fitVideo] re-fits the window to the video's resolution on
/// every video open/switch; [WindowFitMode.fixedWindow] keeps the current
/// size. Priority OVER the video display mode. Metadata-gate era only — the
/// widget is mounted exclusively from the desktop bar (gate OFF renders the
/// legacy autoResize checkbox instead).
class WindowFitModeButton extends HookWidget {
  const WindowFitModeButton({
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
    final mode = useAppStore().select(context, (s) => s.windowFitMode);
    final scheme = useEffectiveKeyboardScheme(context);
    final hint = shortcutHintLabelFor(ShortcutHintKind.autoResize, scheme);

    final (String label, IconData icon) = switch (mode) {
      WindowFitMode.fitVideo => (t.osd_window_fit, Icons.open_in_full_rounded),
      WindowFitMode.fixedWindow =>
        (t.osd_window_fixed, Icons.lock_outline_rounded),
    };

    return a11yTooltipIconButton(
      context: context,
      tooltip: '${t.window_label}: $label ( $hint )',
      icon: Icon(
        icon,
        size: kIconSizeSecondary,
        color: mode == WindowFitMode.fitVideo ? (color ?? Theme.of(context).colorScheme.primary) : color,
      ),
      onPressed: () async {
        showControl();
        await useAppStore().toggleWindowFitMode();
        // Transient centered feedback after the change (PotPlayer parity).
        showPlayerOsd(OsdTexts.windowFitMode(t,
          fitVideo: useAppStore().state.windowFitMode == WindowFitMode.fitVideo,
        ));
      },
      style: ButtonStyle(overlayColor: overlayColor),
    );
  }
}
