/// Back-arrow disposition of the player route (requirement #4).
///
/// The gesture guide is a Stack OVERLAY, not a route: without this branch a
/// bare system back press fell straight through the player's `PopScope`
/// (canPop:false) into saveProgress + app exit — the guide (and its editor
/// round-trip) had no working back path at all. The back arrow now owns the
/// guide first: close the overlay, stay in the player.
enum PlayerBackDisposition {
  /// Guide (or its settings/editor round-trip) is on stage — back closes it.
  closeGestureGuide,

  /// Nothing overlays the player — back keeps its original exit semantics.
  leavePlayer,
}

PlayerBackDisposition resolvePlayerBackDisposition({
  required bool isShowGestureTips,
}) {
  return isShowGestureTips
      ? PlayerBackDisposition.closeGestureGuide
      : PlayerBackDisposition.leavePlayer;
}
