/// Live-audition decision for the A-中心-B alignment editor.
///
/// While the editor is open the FOREGROUND is always the transport master: the
/// playhead keeps advancing and play/pause follows it. The 副音 joins ONLY while
/// the playhead sits inside the edited span [A,B] — the foreground interval whose
/// 1:1 alignment maps real bg content. Outside it (before A the bg position
/// would be negative; after B bg has run out; a silence draft; or no bg loaded)
/// the 副音 stays stopped and the foreground plays alone at its configured
/// volume share.
///
/// Pure and unit-testable: the editor's audition driver only wires the result to
/// the engine/store.
library;

/// What the alignment editor's audition driver must do with the 副音 transport
/// for one position sample.
enum EditorAuditionAction {
  /// Nothing changes.
  none,

  /// The playhead entered [A,B] while playing: align and start the 副音.
  startBg,

  /// The playhead left [A,B] (or playback stopped): stop the 副音.
  stopBg,
}

/// Resolves [EditorAuditionAction] for one live sample.
///
/// `want` is true only when the draft is a playMedia mapping, the 副音 is loaded
/// ([bgReady]), the foreground is playing, and the playhead is inside the
/// inclusive span [spanStartMs, spanEndMs].
EditorAuditionAction resolveEditorAudition({
  required bool isPlayMedia,
  required bool bgReady,
  required bool fgPlaying,
  required bool bgPlaying,
  required int fgPosMs,
  required int spanStartMs,
  required int spanEndMs,
}) {
  final bool want = isPlayMedia &&
      bgReady &&
      fgPlaying &&
      fgPosMs >= spanStartMs &&
      fgPosMs <= spanEndMs;
  if (want) {
    return bgPlaying ? EditorAuditionAction.none : EditorAuditionAction.startBg;
  }
  return bgPlaying ? EditorAuditionAction.stopBg : EditorAuditionAction.none;
}
