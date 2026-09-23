/// Which physical ring hosts the FOREGROUND media in the align editor's
/// dual-ring dial (side type). The 副音 media always takes the other ring —
/// and since the A/P/B handles are drawn on the 副音 ring, the default
/// ([fgOuter]) puts them on the INNER ring.
///
/// The role stays bound to the MEDIA — swapping only moves each media between
/// the inner and outer radius, so the foreground ring keeps driving the
/// foreground player either way.
enum AlignRingAssignment {
  /// Foreground on the inner ring, 副音 on the outer one.
  fgInner,

  /// Foreground on the outer ring, 副音 on the inner one (default).
  fgOuter,
}
