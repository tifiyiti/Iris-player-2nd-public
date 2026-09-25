import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/background_playback/view/control_target_indicator.dart'
    show kBackgroundTargetColor;
import 'package:iris/features/windows/desktop_keyboard/view/shortcut_hints.dart';
import 'package:iris/info.dart';
import 'package:iris/pages/player/title_prefix.dart' show kNoTagSuffix;
import 'package:iris/store/use_player_ui_store.dart';
import 'package:iris/utils/app_exit.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/a11y_tooltip.dart';
import 'package:iris/utils/platform.dart';
import 'package:window_manager/window_manager.dart';

class TitleBar extends HookWidget {
  const TitleBar({
    super.key,
    this.title,
    this.queueLabel,
    this.tagSuffix,
    this.bgTitleSuffix,
    this.bgTitleNoMedia = false,
    this.actions,
    this.color,
    this.overlayColor,
    this.saveProgress,
  });

  final String? title;
  final String? queueLabel;
  final String? tagSuffix;

  /// 副音 on-marker (accent color), appended after the tag suffix — never a
  /// replacement for [title].
  final String? bgTitleSuffix;

  /// 副音 is on but no media is loaded — the marker renders muted (gray)
  /// instead of the accent color.
  final bool bgTitleNoMedia;
  final List<Widget>? actions;
  final Color? color;
  final WidgetStateProperty<Color?>? overlayColor;
  final Future<void> Function()? saveProgress;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final isAlwaysOnTop =
        usePlayerUiStore().select(context, (state) => state.isAlwaysOnTop);
    final isFullScreen =
        usePlayerUiStore().select(context, (state) => state.isFullScreen);
    final scheme = useEffectiveKeyboardScheme(context);
    final fullscreenHint =
        shortcutHintLabelFor(ShortcutHintKind.fullscreen, scheme);
    final pinHint = shortcutHintLabelFor(ShortcutHintKind.alwaysOnTop, scheme);

    return Container(
      padding: isDesktop
          ? const EdgeInsets.fromLTRB(12, 4, 4, 8)
          : const EdgeInsets.fromLTRB(16, 8, 8, 8),
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
      child: ExcludeFocus(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/logo_transparent.png',
              width: 32,
              height: 32,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                children: [
                  if (queueLabel != null) ...[
                    Text(
                      queueLabel!,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: color ?? Colors.white,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      title!.isEmpty ? INFO.title : title!,
                      maxLines: 1,
                      textAlign: TextAlign.start,
                      style: TextStyle(
                        fontSize: 16,
                        overflow: TextOverflow.ellipsis,
                        color: color,
                      ),
                    ),
                  ),
                  if (tagSuffix != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      '· ${tagSuffix == kNoTagSuffix ? t.tag_no_tag : tagSuffix}',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 12,
                        color: tagSuffix == kNoTagSuffix
                            ? Colors.white54
                            : (color ?? Colors.white),
                        fontWeight: tagSuffix == kNoTagSuffix
                            ? FontWeight.w400
                            : FontWeight.w600,
                      ),
                    ),
                  ],
                  if (bgTitleSuffix != null) ...[
                    const SizedBox(width: 6),
                    // Flexible: a long background name ellipsizes instead of
                    // overflowing the bar.
                    Flexible(
                      child: Text(
                        bgTitleSuffix!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        // Same size/weight as the title (no bold): only the
                        // color separates the marker from the subject.
                        style: TextStyle(
                          fontSize: 16,
                          color: bgTitleNoMedia
                              ? Colors.white54
                              : kBackgroundTargetColor,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Row(
              children: [
                ...actions ?? [],
                if (isDesktop) ...[
                  // Reactive 窗口全屏 (maximized) mirror — the one-shot
                  // FutureBuilder missed native paths (Win+Up snap, etc.).
                  Builder(builder: (context) {
                    final isMaximized = usePlayerUiStore()
                        .select(context, (s) => s.isWindowMaximized);
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
                              isAlwaysOnTop
                                  ? Icons.push_pin_rounded
                                  : Icons.push_pin_outlined,
                              size: 18,
                              color: color,
                            ),
                            onPressed:
                                usePlayerUiStore().toggleIsAlwaysOnTop,
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
                              isFullScreen
                                  ? Icons.close_fullscreen_rounded
                                  : Icons.open_in_full_rounded,
                              size: 18,
                              color: color,
                            ),
                            onPressed: () async {
                              usePlayerUiStore()
                                  .updateFullScreen(!isFullScreen);
                            },
                            style: ButtonStyle(overlayColor: overlayColor),
                          ),
                        ),
                        Visibility(
                          visible: !isFullScreen,
                          child: IconButton(
                            onPressed: () => windowManager.minimize(),
                            icon: Icon(
                              Icons.remove_rounded,
                              color: color,
                            ),
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
                      ],
                    );
                  }),
                  IconButton(
                    onPressed: () => AppExit.run(saveProgress),
                    icon: Icon(
                      Icons.close_rounded,
                      color: color,
                    ),
                    style: ButtonStyle(
                      overlayColor: WidgetStateProperty.resolveWith<Color?>(
                          (Set<WidgetState> states) {
                        if (states.contains(WidgetState.pressed)) {
                          return Colors.red.withValues(alpha: 0.4);
                        } else if (states.contains(WidgetState.hovered)) {
                          return Colors.red.withValues(alpha: 0.5);
                        }
                        return null;
                      }),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
