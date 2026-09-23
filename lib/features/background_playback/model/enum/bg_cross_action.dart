/// What a foreground TRANSITION does to the 副音 queue.
///
/// Two independent switches share this type, because the two transitions are
/// not the same event for the user:
/// - moving to a new LIST ITEM — a real media file, or a whole virtual-merged
///   item (`bg.itemSwitch`);
/// - a VIRTUAL video switching to a different physical SEGMENT
///   (`bg.segmentSwitch`).
///
/// Independent from the 作用范围 (`BgApplyScope`): the scope decides WHETHER
/// 副音 applies to the new media at all, and it always wins (leaving the anchor
/// pauses 副音 instead of switching tracks).
enum BgCrossAction {
  /// 正常连播: 副音 keeps playing its current file; the 副音 queue is not
  /// touched (it may still advance on its own natural completion).
  keepPlaying,

  /// 切新 bg: advance the 副音 queue one step so a new track starts.
  newBg,
}
