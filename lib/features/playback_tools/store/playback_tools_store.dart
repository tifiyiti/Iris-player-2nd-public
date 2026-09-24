import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'playback_tools_store.freezed.dart';

/// Ephemeral playback-tools state — never persisted.
///
/// The panel's VISIBILITY resets per session; its POSITION deliberately does
/// not, living in `AppState.frameToolsPanelFraction` (a `screenshot.` AUX row)
/// instead: an open/closed overlay is a per-session convenience, but where you
/// parked it is a layout preference.
@freezed
abstract class PlaybackToolsState with _$PlaybackToolsState {
  const factory PlaybackToolsState({
    @Default(false) bool frameToolsVisible,
  }) = _PlaybackToolsState;
}

/// Owns visibility of the draggable frame-tools float panel (phone).
class PlaybackToolsStore extends Store<PlaybackToolsState> {
  PlaybackToolsStore() : super(const PlaybackToolsState());

  void showFrameTools() => set(state.copyWith(frameToolsVisible: true));

  void hideFrameTools() => set(state.copyWith(frameToolsVisible: false));

  void toggleFrameTools() =>
      set(state.copyWith(frameToolsVisible: !state.frameToolsVisible));
}

PlaybackToolsStore usePlaybackToolsStore() =>
    create(() => PlaybackToolsStore());
