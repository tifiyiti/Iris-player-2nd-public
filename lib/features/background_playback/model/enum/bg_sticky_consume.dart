/// Which handles may "stick" to a foreground boundary and spend the pile
/// bundled on the OPPOSITE end before the window translates.
///
/// Orthogonal to `pAlignKeepMaxLength`: this axis decides WHETHER a drag spends
/// a bundled pile at all, while that setting decides HOW FAR it may spend it
/// (down to the sealed pile, or all the way to zero).
///
/// - P pull-away: while one end sits on the head/tail it holds, the other end
///   follows, and only the pile above its seal is spent before the remainder
///   translates the window.
/// - A/B outward: after the handle's OWN pile is exhausted, an end already on
///   the opposite foreground bound holds and the other end follows, spending
///   that side's pile above its seal before the remainder translates.
enum BgStickyConsume {
  /// Neither handle spends a bundled pile: an outward drag translates the
  /// window immediately (the pre-sticky behavior).
  off,

  /// Only the P (alignment) pull-away spends a bundled pile.
  pOnly,

  /// Only an A/B outward drag spends the opposite end's pile.
  abOnly,

  /// Both surfaces spend bundled piles. The default.
  all;

  /// Whether a P pull-away spends the pile above the seal before translating.
  bool get pSticky => this == BgStickyConsume.pOnly || this == BgStickyConsume.all;

  /// Whether an A/B outward drag spends the opposite end's pile above its seal
  /// after its own pile is exhausted.
  bool get abSticky => this == BgStickyConsume.abOnly || this == BgStickyConsume.all;
}
