/// Display layout of the 副音 (background) video surface while
/// [BackgroundPlaybackState.showBgVideo] is on.
///
/// v1 implements only [BgVideoLayout.fullscreen] (target=副音时全屏切换显示 B
/// 画面、目标=前台时隐藏). `pip` / `split` are reserved placeholders: the enum
/// persists the user's choice but the surface renders exactly like fullscreen —
/// selecting them has no behavior change yet (per product decision).
enum BgVideoLayout {
  fullscreen,
  pip,
  split,
}
