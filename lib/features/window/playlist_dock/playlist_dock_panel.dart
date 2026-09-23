import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/features/background_playback/view/background_queue_panel.dart';
import 'package:iris/features/paginated_browser/paginated_browser_page.dart';
import 'package:iris/features/scenario_playback/view/coordinator/scenario_browser.dart';
import 'package:iris/features/window/playlist_dock/docked_play_queue_data_source.dart';
import 'package:iris/features/window/playlist_dock/resolve_playlist_theme.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/platform.dart';
import 'package:iris/widgets/a11y_tooltip.dart';
import 'package:iris/widgets/popup.dart';

/// Right-side dock panel (PotPlayer-style) showing the play queue.
///
/// Header row: title + toggle floating/docked + close. Body: paginated list
/// without popping on tap (stays docked).
class PlaylistDockPanel extends HookWidget {
  const PlaylistDockPanel({super.key, this.onClose});

  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final mode = useAppStore().select(context, (s) => s.playlistPanelMode);
    final isDocked = mode == PlaylistPanelMode.dockedRight;
    final direction = useAppStore().select(context, (s) => s.defaultPopupDirection);
    // 副音 control target: the dock body presents the background queue
    // (see 交接 §4 错误 1); switch back to foreground restores the normal queue.
    // Reactively subscribe so flipping the control target rebuilds the dock.
    final bgStore = useBackgroundPlaybackStore();
    final bgTarget = bgStore.select(context, (s) => s.bgOwnsControls);
    if (bgTarget) {
      return _BackgroundDockBody(isDocked: isDocked, onClose: onClose);
    }
    // Scenario-driven playback present -> floating scenario queue shares same panel type.
    final useScenario = useAppStore().select(context, (s) => !s.useLegacyStoragePersistence && s.useScenarioDrivenPlayback);
    if (useScenario) {
      return _ScenarioDockBody(
        isDocked: isDocked,
        direction: direction,
        onClose: onClose,
      );
    }
    final dataSource = useMemoized(() => DockedPlayQueueDataSource(), []);
    final dockThemeSetting = useAppStore().select(context, (s) => s.playlistDockTheme);
    final theme = resolvePlaylistDockTheme(context, dockThemeSetting);
    final bg = theme.scaffoldBackgroundColor;
    final divider = theme.dividerColor;

    return Theme(
      data: theme,
      child: Container(
        color: bg,
        child: Column(
          children: [
            _DockHeader(
              isDocked: isDocked,
              dataSource: dataSource,
              onClose: onClose,
            ),
            Divider(height: 1, color: divider),
            Expanded(
              child: PaginatedBrowserPage<PlayQueueItem>(
                dataSource: dataSource,
                onClose: onClose,
                showHomePage: false,
                showBackButton: false,
              ),
            ),
            // Bottom bar removed — actions live in DataSource/PageActions (single source).
          ],
        ),
      ),
    );
  }
}

class _DockHeader extends HookWidget {
  const _DockHeader({required this.isDocked, required this.dataSource, this.onClose});

  final bool isDocked;
  final DockedPlayQueueDataSource dataSource;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    return Container(
      height: 32,
      color: const Color(0xFF252525),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          const Icon(Icons.playlist_play_rounded, size: 16, color: Color(0xFFCCCCCC)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              t.dock_playlist,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFFE0E0E0)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _CountBadge(dataSource: dataSource),
          // AXTree stability (#182444): tap-only tooltip under a UIA client —
          // the overlay mounts at the ROOT overlay, outside the dock's
          // ExcludeSemantics, so it can graft mid-playback.
          if (!isMobilePlatform)
            a11yTooltip(
              context: context,
              message: isDocked
                  ? t.dock_tip_docked
                  : t.dock_tip_floating,
              child: IconButton(
                icon: Icon(
                  isDocked ? Icons.view_sidebar_rounded : Icons.open_in_new_rounded,
                  size: 18,
                  color: isDocked ? const Color(0xFF0078D4) : const Color(0xFFAAAAAA),
                ),
                style: IconButton.styleFrom(
                  backgroundColor: isDocked ? const Color(0x140078D4) : null,
                  minimumSize: const Size(28, 28),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () async {
                  await useAppStore().togglePlaylistPanelMode();
                },
              ),
            ),
          a11yTooltip(
            context: context,
            message: t.close,
            child: IconButton(
              icon: const Icon(Icons.close_rounded, size: 16, color: Color(0xFFAAAAAA)),
              style: IconButton.styleFrom(
                minimumSize: const Size(28, 28),
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onClose,
            ),
          ),
        ],
      ),
    );
  }
}

class _CountBadge extends HookWidget {
  const _CountBadge({required this.dataSource});
  final DockedPlayQueueDataSource dataSource;

  @override
  Widget build(BuildContext context) {
    useListenable(dataSource);
    final total = dataSource.totalItems;
    final pos = usePlayQueueStore().select(
      context,
      (s) => s.playQueue.indexWhere((e) => e.index == s.currentIndex),
    );
    final display = total == 0 ? 0 : (pos >= 0 ? pos + 1 : 1);
    final text = total == 0 ? '0/0' : '$display/$total';
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFFAAAAAA) : theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

/// Scenario-driven dock body: same PaginatedBrowserPage as floating queue, themed via dock setting.
class _ScenarioDockBody extends HookWidget {
  const _ScenarioDockBody({required this.isDocked, required this.direction, this.onClose});
  final bool isDocked;
  final PopupDirection direction;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final dockThemeSetting = useAppStore().select(context, (s) => s.playlistDockTheme);
    final theme = resolvePlaylistDockTheme(context, dockThemeSetting);
    return Theme(
      data: theme,
      child: Container(
        color: theme.scaffoldBackgroundColor,
        child: Column(
          children: [
            _ScenarioDockHeader(isDocked: isDocked, direction: direction, onClose: onClose),
            Divider(height: 1, color: theme.dividerColor),
            Expanded(
              child: ScenarioBrowser(
                direction: direction,
                onExit: onClose != null ? (ctx) => onClose!.call() : null,
                embeddedInStoragesDb: false,
                modeQueueOverride: true,
                // The dock owns the theme (resolvePlaylistDockTheme above); the
                // queue must not repaint itself with the floating-popup theme.
                dockedPanel: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScenarioDockHeader extends HookWidget {
  const _ScenarioDockHeader(
      {required this.isDocked, required this.direction, this.onClose});
  final bool isDocked;
  final PopupDirection direction;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      height: 32,
      color: isDark ? const Color(0xFF252525) : theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Icon(Icons.playlist_play_rounded, size: 16, color: isDark ? const Color(0xFFCCCCCC) : theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              t.dock_playlist,
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: isDark ? const Color(0xFFE0E0E0) : theme.colorScheme.onSurface),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!isMobilePlatform)
            a11yTooltip(
              context: context,
              message: isDocked ? t.dock_tip_docked : t.dock_tip_floating,
              child: IconButton(
                icon: Icon(isDocked ? Icons.view_sidebar_rounded : Icons.open_in_new_rounded, size: 18, color: isDocked ? theme.colorScheme.primary : (isDark ? const Color(0xFFAAAAAA) : theme.colorScheme.onSurfaceVariant)),
                style: IconButton.styleFrom(backgroundColor: isDocked ? theme.colorScheme.primary.withValues(alpha: 0.12) : null, minimumSize: const Size(28, 28), padding: EdgeInsets.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                onPressed: () async => useAppStore().togglePlaylistPanelMode(),
              ),
            ),
          a11yTooltip(
            context: context,
            message: t.close,
            child: IconButton(
              icon: Icon(Icons.close_rounded, size: 16, color: isDark ? const Color(0xFFAAAAAA) : theme.colorScheme.onSurfaceVariant),
              style: IconButton.styleFrom(minimumSize: const Size(28, 28), padding: EdgeInsets.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              onPressed: onClose,
            ),
          ),
        ],
      ),
    );
  }
}

/// Dock body while the control target is the 副音 engine: reuses the shared
/// [BackgroundQueuePanel] wrapped with the dock chrome (header + count).
class _BackgroundDockBody extends HookWidget {
  const _BackgroundDockBody({required this.isDocked, this.onClose});
  final bool isDocked;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = resolvePlaylistDockTheme(
        context, useAppStore().state.playlistDockTheme);
    final t = getLocalizations(context);
    final isDark = theme.brightness == Brightness.dark;
    return Theme(
      data: theme,
      child: Container(
        color: theme.scaffoldBackgroundColor,
        child: Column(
          children: [
            Container(
              height: 32,
              color: isDark ? const Color(0xFF252525) : theme.colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  const Icon(Icons.multitrack_audio_rounded,
                      size: 16, color: Color(0xFF0078D4)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t.bg_queue_title,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: isDark
                              ? const Color(0xFFE0E0E0)
                              : theme.colorScheme.onSurface),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!isMobilePlatform)
                    a11yTooltip(
                      context: context,
                      message: isDocked ? t.dock_tip_docked : t.dock_tip_floating,
                      child: IconButton(
                        icon: Icon(
                          isDocked
                              ? Icons.view_sidebar_rounded
                              : Icons.open_in_new_rounded,
                          size: 18,
                          color: isDocked
                              ? const Color(0xFF0078D4)
                              : const Color(0xFFAAAAAA),
                        ),
                        style: IconButton.styleFrom(
                          minimumSize: const Size(28, 28),
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () async {
                          await useAppStore().togglePlaylistPanelMode();
                        },
                      ),
                    ),
                  a11yTooltip(
                    context: context,
                    message: t.close,
                    child: IconButton(
                      icon: const Icon(Icons.close_rounded,
                          size: 16, color: Color(0xFFAAAAAA)),
                      style: IconButton.styleFrom(
                          minimumSize: const Size(28, 28),
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      onPressed: onClose,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: theme.dividerColor),
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Center(
                    child: BackgroundQueuePanel(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
