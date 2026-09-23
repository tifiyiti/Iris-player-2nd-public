/// Which quick 副音 floating panel is open.
///
/// The quick bar (and the 副音 menu) open these as NON-MODAL draggable cards
/// mounted in the player Stack — playback and gestures stay live underneath,
/// and the video is never dimmed. Only one is open at a time; [none] closes
/// every card. Session-only: never persisted.
enum BgQuickPanel {
  none,
  scope,
  ratio,
  align,
}
