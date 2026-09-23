import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/features/background_playback/view/control_target_indicator.dart';
import 'package:iris/features/background_playback/view/segment_align_edit_panel.dart';
import 'package:iris/features/phone/one_handed_scrubber/controller/sideway_panel_layout.dart';
import 'package:iris/globals.dart' show controlPanelKeyNotifier;
import 'package:iris/hooks/use_published_global_key.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/models/store/phone_landscape_slider_type_helper.dart';
import 'package:iris/pages/player/control_bar/control_bar.dart';
import 'package:iris/pages/player/control_bar/control_bar_widgets/control_bar_constants.dart';
import 'package:iris/pages/player/control_bar/legacy_control_bar.dart';
import 'package:iris/pages/player/control_bar/title_area.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:iris/store/use_scrub_drag_store.dart';
import 'package:iris/utils/platform.dart';
import 'package:iris/widgets/drag_area.dart';
import 'package:provider/provider.dart';

class ControlsOverlay extends HookWidget {
  const ControlsOverlay({
    super.key,
    required this.file,
    required this.title,
    this.queueLabel,
    this.tagSuffix,
    this.bgTitleSuffix,
    this.bgTitleNoMedia = false,
    required this.showControl,
    required this.showControlForHover,
    required this.hideControl,
    required this.showProgress,
    this.showTitleOnly,
  });

  final FileItem? file;
  final String title;
  final String? queueLabel;
  final String? tagSuffix;

  /// 副音 on-marker appended to the title (see [TitleArea]).
  final String? bgTitleSuffix;

  /// 副音 is on but no media is loaded — the marker renders muted (see
  /// [TitleArea]).
  final bool bgTitleNoMedia;
  final Function() showControl;
  final Future<void> Function(Future<void> callback) showControlForHover;
  final Function() hideControl;
  final Function() showProgress;
  final Function()? showTitleOnly;

  @override
  Widget build(BuildContext context) {
    final saveProgress = context.read<MediaPlayer>().saveProgress;

    final isShowControl = usePlayerUiStore().select(context, (state) => state.isShowControl);

    final contentColor = useMemoized(
        () => Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).colorScheme.onSurface
            : Theme.of(context).colorScheme.surface,
        [context]);

    final width = MediaQuery.sizeOf(context).width;
    final PhoneLandscapeUseMode phoneLandscapeUseMode =
        useAppStore().select(context, (state) => state.phoneLandscapeUseMode);
    final AppState appState = useAppStore().select(context, (s) => s);
    final ScreenOrientation runtimeOrientation =
        useAppStore().select(context, (state) => state.runtimeOrientation);
    final controlsTitleConfig = useAppStore().select(context, (state) => state.controlsTitleConfig);
    final useLegacy = useAppStore().select(context, (state) => state.useLegacyControlBar);

    final bool isLandscape = isLandscapeOrientation(
      runtimeOrientation: runtimeOrientation,
      realOrientation: MediaQuery.orientationOf(context),
    );
    // Single authority for the panel's screen anchor (shared with the panel's
    // bottom button rows, which face the screen centre).
    final Alignment controlBarOverlayAlignment = resolveControlPanelAnchor(
      appState,
      isLandscape: isLandscape,
      width: width,
    );

    final overlayColor = useMemoized(
        () => WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
              if (states.contains(WidgetState.pressed)) {
                return contentColor.withValues(alpha: 0.2);
              } else if (states.contains(WidgetState.hovered)) {
                return contentColor.withValues(alpha: 0.2);
              }
              return null;
            }),
        [contentColor]);

    void onHover(PointerHoverEvent event) {
      if (event.kind != PointerDeviceKind.touch) {
        final bool rc = shouldRequireClickToShowPanel(appState);
        final bool armed = usePlayerUiStore().state.isPanelClickArmed;
        final bool holding = useScrubDragStore().state.any;
        final bool isVideo = file?.type == ContentType.video;
        final bool hiddenForRc = rc && isVideo && !holding && !armed;
        if (hiddenForRc) {
          // Hidden: hover only shows title/cursor
          if (showTitleOnly != null) {
            showTitleOnly!.call();
          } else {
            usePlayerUiStore().updateIsShowControl(true);
            usePlayerUiStore().updateIsHovering(true);
            showControl();
          }
        } else {
          usePlayerUiStore().updateIsHovering(true);
          showControl();
        }
      }
    }

    // tap on title / panel: when requireClick is ON, arm the panel
    void handlePanelTap() {
      final bool requireClick = shouldRequireClickToShowPanel(appState);
      if (requireClick) {
        final ui = usePlayerUiStore().state;
        if (!ui.isPanelClickArmed) {
          usePlayerUiStore().updateIsPanelClickArmed(true);
        }
      }
      showControl();
    }

    final bool isPanelClickArmed =
        usePlayerUiStore().select(context, (s) => s.isPanelClickArmed);
    final bool isHoverReveal =
        usePlayerUiStore().select(context, (s) => s.isHoverReveal);
    final bool dragActive = useScrubDragStore().select(context, (s) => s.any);
    // The align editor replaces the bar and is ALWAYS shown while open — no
    // auto-hide, no click requirement, no tap-away dismissal.
    final bool editing = useBackgroundPlaybackStore()
        .select(context, (s) => s.segmentEditMode);
    // Passive hover only: `app.desktopHoverShow*` decide what it reveals.
    // Explicit shows (startup / click / key) ignore the switches entirely.
    final bool titleRevealed =
        !isHoverReveal || desktopHoverRevealsTitle(appState);
    // Shared with every affordance that rides WITH the panel (see
    // `resolveControlPanelVisible`).
    final bool isShowSidePanel = resolveControlPanelVisible(
      appState: appState,
      isShowControl: isShowControl,
      isHoverReveal: isHoverReveal,
      isPanelClickArmed: isPanelClickArmed,
      editing: editing,
      isVideo: file?.type == ContentType.video,
      dragActive: dragActive,
    );

    // Direction-aware hide translation: side total panel per actual panel size
    // + anchor (9-grid); linear bottom bars fall back to downward slide.
    final Size windowSize = MediaQuery.sizeOf(context);
    // Per-mount key of the BAR box itself (published for the picture-fullscreen
    // playlist dock, which excludes it from its right-edge summon strip — see
    // `controlPanelKeyNotifier`). It wraps the translated box, so a hidden bar
    // reports an off-screen rect and cannot block the dock's strip.
    final GlobalKey controlPanelKey =
        usePublishedGlobalKey(controlPanelKeyNotifier);
    final bool isSideLayout = (isWindows || (isMobilePlatform && isLandscape)) &&
        phoneLandscapeUseMode.usesOneHandedControls;
    late final Offset hideTranslate;
    if (isSideLayout) {
      final bool isPhone = isMobilePlatform;
      final ({double panelW, double panelH}) panel = panelSizeForWindow(
        windowW: windowSize.width,
        windowH: windowSize.height,
        isPhone: isPhone,
        widthPct: appState.sidewayPanelWidthPct,
        heightPct: appState.sidewayPanelHeightPct,
        widthPx: appState.sidewayPanelWidthPx,
        heightPx: appState.sidewayPanelHeightPx,
      );
      hideTranslate = hideTranslateForAnchor(
        anchor: controlBarOverlayAlignment,
        isLeftHanded: phoneLandscapeUseMode.isLeftHanded,
        panelW: panel.panelW,
        panelH: panel.panelH,
        cornerMode: appState.sidePanelCornerHideMode,
      );
    } else {
      // Linear bars (desktop single/stacked, tablet, phone portrait) slide down.
      hideTranslate = Offset(0, windowSize.height + 24);
    }

    return Stack(
      children: [
        // 标题栏 - hover always shows title/cursor via normal showControl
        AnimatedPositioned(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOutCubicEmphasized,
          top: (isShowControl && titleRevealed) ||
                  file?.type != ContentType.video
              ? 0
              : kTitleBarHiddenOffset,
          left: 0,
          right: 0,
          child: MouseRegion(
            onHover: onHover,
            child: GestureDetector(
              onTap: handlePanelTap,
              child: DragArea(
                child: TitleArea(
                  title: title,
                  queueLabel: queueLabel,
                  tagSuffix: tagSuffix,
                  bgTitleSuffix: bgTitleSuffix,
                  bgTitleNoMedia: bgTitleNoMedia,
                  color: contentColor,
                  overlayColor: overlayColor,
                  saveProgress: () => saveProgress(),
                  config: controlsTitleConfig,
                ),
              ),
            ),
          ),
        ),
        // 控制栏 - direction-aware hide (手机/桌面按实际面板高，电脑按锚点方位；边中单轴、四角对角、正中按 side)
        Positioned.fill(
          child: Align(
            alignment: controlBarOverlayAlignment,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOutCubicEmphasized,
              transform: Matrix4.translationValues(
                isShowSidePanel ? 0 : hideTranslate.dx,
                isShowSidePanel ? 0 : hideTranslate.dy,
                0,
              ),
              // The 副音 target frame sits INSIDE the transform, wrapping the
              // bar itself. Outside it (or around the full-screen fill) the
              // border is painted at the untranslated box and stays on screen
              // while the bar slides away — which read as "only a blue frame,
              // no control bar".
              child: BackgroundControlTargetIndicator(
                borderRadius: BorderRadius.all(Radius.circular(
                  isSideLayout ? 12 : 0,
                )),
                child: ConstrainedBox(
                  key: controlPanelKey,
                  constraints: BoxConstraints(
                    maxHeight: windowSize.height,
                    maxWidth: windowSize.width,
                  ),
                  child: IgnorePointer(
                    ignoring: !isShowSidePanel,
                    child: ExcludeSemantics(
                      excluding: !isShowSidePanel,
                      child: TickerMode(
                        enabled: isShowSidePanel,
                        child: MouseRegion(
                          onHover: onHover,
                          child: GestureDetector(
                            onTap: handlePanelTap,
                            child: editing
                                ? SegmentAlignEditPanel(
                                    isSide: isSideLayout,
                                    color: contentColor,
                                    overlayColor: overlayColor,
                                    showControl: showControl,
                                  )
                                : useLegacy
                                    ? LegacyControlBar(
                                        showControl: showControl,
                                        showControlForHover: showControlForHover,
                                        color: contentColor,
                                        overlayColor: overlayColor,
                                      )
                                    : ControlBar(
                                        showControl: showControl,
                                        showControlForHover: showControlForHover,
                                        color: contentColor,
                                        overlayColor: overlayColor,
                                      ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
