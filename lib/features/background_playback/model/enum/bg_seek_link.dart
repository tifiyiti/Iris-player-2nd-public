/// Whether a foreground seek moves the 副音 runtime with it.
///
/// One of the two orthogonal axes the old three-value 进度锁定 was split into
/// (the other is [BgLockLevel]). [independent] wins over the level axis: when
/// the two runtimes are fully independent nothing is shared at all.
enum BgSeekLink {
  /// Seeks (and play/pause, per the level axis) keep the two in step.
  linked,

  /// Nothing is shared — the two runtimes never influence each other.
  independent,
}

/// How strongly the shared transport mirrors the foreground.
///
/// Meaningful only while [BgSeekLink.linked] (fully independent overrides it).
enum BgLockLevel {
  /// Play/pause AND seek forward/back step follow the foreground.
  high,

  /// Only play/pause follows; seeks stay manual.
  low,
}
