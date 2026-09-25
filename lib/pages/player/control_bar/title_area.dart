import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/windows/desktop_keyboard/view/shortcut_hints.dart';
import 'package:iris/models/store/title_overlay_config.dart';
import 'package:iris/pages/player/overlays/overlay_part/title_overlay.dart';
import 'package:iris/pages/player/title_bar.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:iris/utils/app_exit.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/platform.dart';
import 'package:iris/widgets/a11y_tooltip.dart';
import 'package:iris/widgets/drag_area.dart';
import 'package:window_manager/window_manager.dart';

class TitleArea extends HookWidget {
  const TitleArea({
    super.key,
    required this.title,
    this.queueLabel,
    this.tagSuffix,
    this.bgTitleSuffix,
    this.bgTitleNoMedia = false,
    required this.saveProgress,
    required this.color,
    required this.overlayColor,
    required this.config,
  });

  final String title;
  final String? queueLabel;
  final String? tagSuffix;

  /// 副音 on-marker: the background media's name, appended in the accent
  /// color after the foreground title (never a replacement).
  final String? bgTitleSuffix;

  /// 副音 is on but no media is loaded — the marker renders muted (gray).
  final bool bgTitleNoMedia;
  final Future<void> Function()? saveProgress;
  final Color? color;
  final WidgetStateProperty<Color?>? overlayColor;
  final TitleOverlayConfig config;

  @override
  Widget build(BuildContext context) {
    final useClassic = useAppStore().select(context, (s) => s.useClassicTitleBar);

    if (useClassic) {
      return TitleBar(
        title: title,
        queueLabel: queueLabel,
        tagSuffix: tagSuffix,
        bgTitleSuffix: bgTitleSuffix,
        bgTitleNoMedia: bgTitleNoMedia,
        color: color,
        overlayColor: overlayColor,
        saveProgress: saveProgress,
      );
    }

    return CustomTitleOverlayBar(
      title: title,
      queueLabel: queueLabel,
      tagSuffix: tagSuffix,
      bgTitleSuffix: bgTitleSuffix,
      bgTitleNoMedia: bgTitleNoMedia,
      saveProgress: saveProgress,
      color: color,
      overlayColor: overlayColor,
      config: config,
    );
  }
}

class CustomTitleOverlayBar extends HookWidget {
  const CustomTitleOverlayBar(
      {super.key,
      required this.title,
      this.queueLabel,
      this.tagSuffix,
      this.bgTitleSuffix,
      this.bgTitleNoMedia = false,
      required this.saveProgress,
      required this.color,
      required this.overlayColor,
      required this.config});

  final String title;
  final String? queueLabel;
  final String? tagSuffix;
  final String? bgTitleSuffix;
  final bool bgTitleNoMedia;
  final Future<void> Function()? saveProgress;
  final Color? color;
  final WidgetStateProperty<Color?>? overlayColor;
  final TitleOverlayConfig config;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: isDesktop ? const EdgeInsets.fromLTRB(12, 4, 4, 8) : const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black87.withValues(alpha: 0.6),
            Colors.black87.withValues(alpha: 0.25),
            Colors.black87.withValues(alpha: 0),
          ],
        ),
      ),
      child: DragArea(
        child: Row(
          children: [
            // NEW title overlay content
            Expanded(
              child: TitleOverlayView(
                config: config,
                title: title,
                queueLabel: queueLabel,
                tagSuffix: tagSuffix,
                bgTitleSuffix: bgTitleSuffix,
                bgTitleNoMedia: bgTitleNoMedia,
                queueIndex: null, // wire your real index here
                showIcon: true,
              ),
            ),
            if (isDesktop)
              DesktopWindowControls(
                color: color,
                overlayColor: overlayColor,
                saveProgress: saveProgress,
              ),
          ],
        ),
      ),
    );
  }
}

class DesktopWindowControls extends HookWidget {
  const DesktopWindowControls({
    super.key,
    required this.color,
    required this.overlayColor,
    required this.saveProgress,
  });

  final Color? color;
  final WidgetStateProperty<Color?>? overlayColor;
  final Future<void> Function()? saveProgress;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final isAlwaysOnTop = usePlayerUiStore().select(context, (s) => s.isAlwaysOnTop);
    final isFullScreen = usePlayerUiStore().select(context, (s) => s.isFullScreen);
    // Reactive 窗口全屏 (maximized) mirror — the one-shot FutureBuilder
    // missed native paths (Win+Up snap, etc.).
    final isMaximized = usePlayerUiStore().select(context, (s) => s.isWindowMaximized);
    final scheme = useEffectiveKeyboardScheme(context);
    final pinHint = shortcutHintLabelFor(ShortcutHintKind.alwaysOnTop, scheme);
    final fullscreenHint =
        shortcutHintLabelFor(ShortcutHintKind.fullscreen, scheme);

    return Row(
      children: [
        Visibility(
          visible: !isFullScreen,
          child: a11yTooltipIconButton(
            context: context,
            tooltip: isAlwaysOnTop
                ? '${t.always_on_top_on} ( $pinHint )'
                : '${t.always_on_top_off} ( $pinHint )',
            icon: Icon(
              isAlwaysOnTop ? Icons.push_pin_rounded : Icons.push_pin_outlined,
              size: 18,
              color: color,
            ),
            onPressed: usePlayerUiStore().toggleIsAlwaysOnTop,
            style: ButtonStyle(overlayColor: overlayColor),
          ),
        ),
        Visibility(
          visible: isFullScreen,
          child: a11yTooltipIconButton(
            context: context,
            tooltip: isFullScreen
                ? '${t.exit_fullscreen} ( $fullscreenHint )'
                : '${t.enter_fullscreen} ( $fullscreenHint )',
            icon: Icon(
              isFullScreen ? Icons.close_fullscreen_rounded : Icons.open_in_full_rounded,
              size: 18,
              color: color,
            ),
            onPressed: () {
              usePlayerUiStore().updateFullScreen(!isFullScreen);
            },
            style: ButtonStyle(overlayColor: overlayColor),
          ),
        ),
        Visibility(
          visible: !isFullScreen,
          child: IconButton(
            onPressed: () => windowManager.minimize(),
            icon: Icon(Icons.remove_rounded, color: color),
            style: ButtonStyle(overlayColor: overlayColor),
          ),
        ),
        Visibility(
          visible: !isFullScreen,
          child: IconButton(
            onPressed: usePlayerUiStore().toggleWindowMaximize,
            icon: isMaximized
                ? RotatedBox(
                    quarterTurns: 2,
                    child: Icon(
                      Icons.filter_none_rounded,
                      size: 18,
                      color: color,
                    ),
                  )
                : Icon(
                    Icons.crop_din_rounded,
                    size: 20,
                    color: color,
                  ),
            style: ButtonStyle(overlayColor: overlayColor),
          ),
        ),
        IconButton(
          onPressed: () => AppExit.run(saveProgress),
          icon: Icon(Icons.close_rounded, color: color),
          style: ButtonStyle(
            overlayColor: WidgetStateProperty.resolveWith<Color?>(
              (states) {
                if (states.contains(WidgetState.pressed)) {
                  return Colors.red.withValues(alpha: 0.4);
                } else if (states.contains(WidgetState.hovered)) {
                  return Colors.red.withValues(alpha: 0.5);
                }
                return null;
              },
            ),
          ),
        ),
      ],
    );
  }
}
