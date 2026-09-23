import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/windows/desktop_keyboard/view/shortcut_hints.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/pages/player/control_bar/control_bar_widgets/control_bar_constants.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/platform.dart';
import 'package:iris/widgets/a11y_tooltip.dart';

/// Desktop-only toggle between the docked-right playlist panel and the
/// floating popup. Renders nothing when non-desktop or the metadata gate is
/// off, so it is safe to mount unconditionally in the desktop control bar.
class PlaylistDockModeButton extends HookWidget {
  const PlaylistDockModeButton({
    super.key,
    required this.showControl,
    this.color,
    this.overlayColor,
  });

  final VoidCallback showControl;
  final Color? color;
  final WidgetStateProperty<Color?>? overlayColor;

  @override
  Widget build(BuildContext context) {
    final useMetadataSettings =
        useAppStore().select(context, (s) => s.useMetadataSettings);
    final playlistPanelMode =
        useAppStore().select(context, (s) => s.playlistPanelMode);
    final scheme = useEffectiveKeyboardScheme(context);

    if (!isDesktop) return const SizedBox.shrink();
    if (!useMetadataSettings) return const SizedBox.shrink();

    final bool isDocked = playlistPanelMode == PlaylistPanelMode.dockedRight;
    final String? hint = shortcutHintLabelFor(
      ShortcutHintKind.playlistDockMode,
      scheme,
    );
    final t = getLocalizations(context);
    // Unified 20px with the rest of the bottom Wrap; on/off is a subtle
    // transparent-white delta, not a primary-color highlight.
    final Color base = color ?? Colors.white.withValues(alpha: 0.90);
    return a11yTooltipIconButton(
      context: context,
      tooltip: isDocked
          ? t.dock_tip_docked_full(hint ?? '')
          : t.dock_tip_floating_full(hint ?? ''),
      icon: Container(
        width: kIconSizeSecondary + 6,
        height: kIconSizeSecondary + 6,
        // decoration: isDocked
        //     ? BoxDecoration(
        //         shape: BoxShape.circle,
        //         color: Colors.white.withValues(alpha: 0.12),
        //         border: Border.all(color: Colors.white.withValues(alpha: 0.45), width: 1),
        //       )
        //     : null,
        alignment: Alignment.center,
        child: Icon(
          isDocked ? Icons.view_sidebar_rounded : Icons.open_in_new_rounded,
          size: kIconSizeSecondary,
          color: isDocked ? Colors.white.withValues(alpha: 0.96) : base.withValues(alpha: 0.88),
        ),
      ),
      onPressed: () {
        showControl();
        useAppStore().togglePlaylistPanelMode();
      },
      style: ButtonStyle(overlayColor: overlayColor),
    );
  }
}