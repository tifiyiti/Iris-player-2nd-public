import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'player_ui_state.freezed.dart';
part 'player_ui_state.g.dart';

@freezed
abstract class PlayerUiState with _$PlayerUiState {
  const factory PlayerUiState({
    @Default(0) double aspectRatio,

    /// Decoded video resolution in physical pixels (0 = unknown). Updated by
    /// both backends alongside [aspectRatio]; consumed by the desktop
    /// window-fit (1:1 resolution sizing).
    @Default(0) double videoWidth,
    @Default(0) double videoHeight,
    @Default(false) bool isAlwaysOnTop,
    @Default(false) bool isFullScreen,

    /// 窗口全屏 (maximized, the title-bar button between minimize and close).
    /// Reactive mirror of the OS state — native maximize (Win+Up snap,
    /// double-click) also lands here via the WindowListener. Together with
    /// [isFullScreen] this yields the three-state model:
    /// 窗口非全屏 = !isFullScreen && !isWindowMaximized /
    /// 窗口全屏 = isWindowMaximized / 画面全屏 = isFullScreen.
    @Default(false) bool isWindowMaximized,
    @Default(false) bool pendingCompleted,
    @Default(false) bool isHovering,
    /// When `sidewayPanelRequireClick` is ON, bottom panel only shows after a
    /// tap/click (hover still shows title/cursor). Runtime-only latch cleared
    /// on hide.
    @Default(false) bool isPanelClickArmed,

    /// True while the current visible state was revealed by a PASSIVE mouse
    /// hover (via `showTitleOnly`), not by an explicit show (startup, click,
    /// keyboard, wheel). Only then do the `desktopHoverShow*` switches gate the
    /// title/panel; explicit shows always ignore them. Runtime-only.
    @Default(false) bool isHoverReveal,
    @Default(true) bool isShowControl,
    @Default(false) bool isShowProgress,
    @Default(false) bool isShowGestureTips,

    /// Last viewed gesture-guide page (runtime-only). Survives hide/show
    /// cycles so the settings/editor round-trip reopens the guide on the
    /// exact page and action map the user left.
    @Default(0) int gestureGuidePage,
    @Default(false) bool isTransientSpeedActive,

    /// Picture-fullscreen (画面全屏) side dock — runtime-only hover "peek".
    /// While set, the right-edge overlay panel is shown even though the user
    /// has not pinned it. Driven by the edge hot-zone / panel hover and
    /// cleared when the pointer leaves the panel (+5px margin).
    @Default(false) bool isFullscreenDockPeeking,

    /// Picture-fullscreen side dock pinned open. Initialized from
    /// [SideFullscreenBehavior.keepPanel] when entering picture fullscreen and
    /// toggled by the P key / control-bar button. Runtime-only: it never
    /// mutates the windowed, persisted `playlistPanelVisible`.
    @Default(false) bool isFullscreenDockPinned,
  }) = _PlayerUiState;

  factory PlayerUiState.fromJson(Map<String, dynamic> json) => _$PlayerUiStateFromJson(json);
}
