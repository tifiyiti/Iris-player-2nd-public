// control_bar_constants.dart

// Layout
const double kVolumeSliderWidth = 160.0;

// Overflow model (see `control_bar_layout/resolve_control_bar_overflow.dart`).
// Nominal footprint of one icon button in a linear bar row. `IconButton`'s
// default padded tap target is 48px; a slightly generous estimate only ever
// collapses a control EARLIER, so the bar can never clip.
const double kControlBarIconButtonWidth = 48.0;

// Minimum width the seek axis must keep for the bar to stay usable; the
// overflow resolver never squeezes the slider below this.
const double kControlBarSliderMinWidth = 120.0;

// Icon sizes — legacy grades kept as-is (PlayPause is the primary
// affordance). Only the docked-playlist toggle is unified to secondary.
const double kIconSizePlayPause = 32.0;
const double kIconSizePrimary = 26.0;
const double kIconSizeSecondary = 20.0;
const double kIconSizeSmall = 18.0;

const double kFullscreenIconSize = 19.0;
const double kPlayQueueIconSize = 28.0;

// Spacing (reserved for future use)

// Overlay animation offsets
const double kTitleBarHiddenOffset = -72.0; // used for slide-up animation
const double kControlBarHiddenOffset = -628.0; // hide control bar completely

// Gradient
const double kOverlayGradientTopOpacity = 0.0;
const double kOverlayGradientMidOpacity = 0.25;
const double kOverlayGradientBottomOpacity = 0.65;

// Volume breakpoint
const double kVolumeControlBreakpoints = 768.0;

// control_bar_constants.dart

// Popup menu
const double kPopupMenuMinWidth = 200.0;
const double kMenuTileIconSize = 20.0; // for menu items (speed, circle slider, history, settings, exit, gesture)
const double kMenuTileIconSizeTiny = 16.5; // for open file / open link items
const double kMenuTextFontSizeShortcut = 12.0; // for trailing shortcut texts
