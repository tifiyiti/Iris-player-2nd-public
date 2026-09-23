import 'package:flutter/cupertino.dart';
import 'package:iris/models/store/gesture_region.dart';

const Rect kFullScreen = Rect.fromLTWH(0, 0, 1, 1);
// Horizontal halves
const Rect kLeftHalf = Rect.fromLTWH(0, 0, 0.5, 1);
const Rect kRightHalf = Rect.fromLTWH(0.5, 0, 0.5, 1);

const Rect kLeft30 = Rect.fromLTWH(0.0, 0, 0.3, 1);
const Rect kMid40 = Rect.fromLTWH(0.3, 0, 0.4, 1);
const Rect kRight30 = Rect.fromLTWH(0.7, 0, 0.3, 1);

const Rect kLeftQuarter = Rect.fromLTWH(0, 0, 0.25, 1);
const Rect kMiddleHalf = Rect.fromLTWH(0.25, 0, 0.5, 1);
const Rect kRightQuarter = Rect.fromLTWH(0.75, 0, 0.25, 1);

// Vertical thirds (35 / 35 / 30)
const Rect kVTop35 = Rect.fromLTWH(0, 0.00, 1, 0.35);
const Rect kVMid35 = Rect.fromLTWH(0, 0.35, 1, 0.35);
const Rect kVBot30 = Rect.fromLTWH(0, 0.70, 1, 0.30);

/// Top strip reserved for the tag-play sheet trigger (meta unified).
/// 0.15 is the final spec (physically partitioned, no priority overlap).
/// Eight-grid: top row is split into two 15% tag cells.
const Rect kTagTop15 = Rect.fromLTWH(0, 0.00, 1, 0.15);
const Rect kTagTop15Left = Rect.fromLTWH(0, 0.00, 0.5, 0.15);
const Rect kTagTop15Right = Rect.fromLTWH(0.5, 0.00, 0.5, 0.15);
@Deprecated('Use kTagTop15')
const Rect kVTop12 = Rect.fromLTWH(0, 0.00, 1, 0.12);

// Portrait 3×3 grid cells (vertical lines 0.33/0.67 × horizontal lines 0.20/0.80)
// Proportions: top 20%, middle 60%, bottom 20%. Widths: 33%, 34%, 33%.
const Rect kGridTagTopLeft = Rect.fromLTWH(0.00, 0.00, 0.33, 0.20);
const Rect kGridTagTopCenter = Rect.fromLTWH(0.33, 0.00, 0.34, 0.20);
const Rect kGridTagTopRight = Rect.fromLTWH(0.67, 0.00, 0.33, 0.20);
const Rect kGridMidLeft = Rect.fromLTWH(0.00, 0.20, 0.33, 0.60);
const Rect kGridMidCenter = Rect.fromLTWH(0.33, 0.20, 0.34, 0.60);
const Rect kGridMidRight = Rect.fromLTWH(0.67, 0.20, 0.33, 0.60);
const Rect kGridBotLeft = Rect.fromLTWH(0.00, 0.80, 0.33, 0.20);
const Rect kGridBotCenter = Rect.fromLTWH(0.33, 0.80, 0.34, 0.20);
const Rect kGridBotRight = Rect.fromLTWH(0.67, 0.80, 0.33, 0.20);

// Landscape 4×3 grid cells (vertical lines 0.25/0.50/0.75 × horizontal lines 0.35/0.70)
// Proportions: top 35%, middle 35%, bottom 30%. Widths: four equal 25% columns.
const Rect kLandscapeCol1Row1 = Rect.fromLTWH(0.00, 0.00, 0.25, 0.35);
const Rect kLandscapeCol2Row1 = Rect.fromLTWH(0.25, 0.00, 0.25, 0.35);
const Rect kLandscapeCol3Row1 = Rect.fromLTWH(0.50, 0.00, 0.25, 0.35);
const Rect kLandscapeCol4Row1 = Rect.fromLTWH(0.75, 0.00, 0.25, 0.35);

const Rect kLandscapeCol1Row2 = Rect.fromLTWH(0.00, 0.35, 0.25, 0.35);
const Rect kLandscapeCol2Row2 = Rect.fromLTWH(0.25, 0.35, 0.25, 0.35);
const Rect kLandscapeCol3Row2 = Rect.fromLTWH(0.50, 0.35, 0.25, 0.35);
const Rect kLandscapeCol4Row2 = Rect.fromLTWH(0.75, 0.35, 0.25, 0.35);

const Rect kLandscapeCol1Row3 = Rect.fromLTWH(0.00, 0.70, 0.25, 0.30);
const Rect kLandscapeCol2Row3 = Rect.fromLTWH(0.25, 0.70, 0.25, 0.30);
const Rect kLandscapeCol3Row3 = Rect.fromLTWH(0.50, 0.70, 0.25, 0.30);
const Rect kLandscapeCol4Row3 = Rect.fromLTWH(0.75, 0.70, 0.25, 0.30);

// Physical partition: below the tag strip (0.15–1.00, height 0.85)
const Rect kLeftQuarterBelow = Rect.fromLTWH(0, 0.15, 0.25, 0.85);
const Rect kMiddleHalfBelow = Rect.fromLTWH(0.25, 0.15, 0.50, 0.85);
const Rect kRightQuarterBelow = Rect.fromLTWH(0.75, 0.15, 0.25, 0.85);

// Six-cell below variants (rightSide/leftSide)
const Rect kLeftTop35Below = Rect.fromLTWH(0.0, 0.15, 0.5, 0.35 * 0.85);
const Rect kLeftMid35Below = Rect.fromLTWH(0.0, 0.15 + 0.35 * 0.85, 0.5, 0.35 * 0.85);
const Rect kLeftBottom30Below = Rect.fromLTWH(0.0, 0.15 + 0.70 * 0.85, 0.5, 0.30 * 0.85);
const Rect kRightTop35Below = Rect.fromLTWH(0.5, 0.15, 0.5, 0.35 * 0.85);
const Rect kRightMid35Below = Rect.fromLTWH(0.5, 0.15 + 0.35 * 0.85, 0.5, 0.35 * 0.85);
const Rect kRightBot30Below = Rect.fromLTWH(0.5, 0.15 + 0.70 * 0.85, 0.5, 0.30 * 0.85);

// Portrait tag: middle column lower 30% (x 0.25-0.75, y 0.70-1.00), not occupying seekB/seekF
const Rect kPortraitMiddleTop70 = Rect.fromLTWH(0.25, 0, 0.50, 0.70);
const Rect kPortraitTagBottom30 = Rect.fromLTWH(0.25, 0.70, 0.50, 0.30);

// Default 6-grid middle column: ONE line at 30% (y 0.70) splits the middle
// into a single playPause cell above and the tag zone below.
const Rect kMiddleTop55Below = Rect.fromLTWH(0.25, 0.15, 0.50, 0.55);
const Rect kMiddleBottom30 = kPortraitTagBottom30;
@Deprecated('Default is now 6-grid: use kMiddleTop55Below / kMiddleBottom30')
const Rect kMiddleTop35Below = Rect.fromLTWH(0.25, 0.15, 0.50, 0.35 * 0.85);
@Deprecated('Default is now 6-grid: use kMiddleTop55Below / kMiddleBottom30')
const Rect kMiddleMid35Below = Rect.fromLTWH(0.25, 0.15 + 0.35 * 0.85, 0.50, 0.35 * 0.85);
@Deprecated('Default is now 6-grid: use kMiddleBottom30')
const Rect kMiddleBottom30Below = Rect.fromLTWH(0.25, 0.15 + 0.70 * 0.85, 0.50, 0.30 * 0.85);

// 6-cell tap grid (2 × 3), rows 25% / 30% / 45% (bottom band toggles controls)
// Left side
const Rect kLeftTop25 = Rect.fromLTWH(0.0, 0.00, 0.5, 0.25);
const Rect kLeftMid30 = Rect.fromLTWH(0.0, 0.25, 0.5, 0.30);
const Rect kLeftBottom45 = Rect.fromLTWH(0.0, 0.55, 0.5, 0.45);

// Right side
const Rect kRightTop25 = Rect.fromLTWH(0.5, 0.00, 0.5, 0.25);
const Rect kRightMid30 = Rect.fromLTWH(0.5, 0.25, 0.5, 0.30);
const Rect kRightBot45 = Rect.fromLTWH(0.5, 0.55, 0.5, 0.45);

// Vertical-pan strips
// Right side
const Rect kRightBrightness = Rect.fromLTWH(0.50, 0, 0.25, 1);
const Rect kRightVolume = Rect.fromLTWH(0.75, 0, 0.25, 1);

// Left side
const Rect kLeftBrightness = Rect.fromLTWH(0.00, 0, 0.25, 1);
const Rect kLeftVolume = Rect.fromLTWH(0.25, 0, 0.25, 1);

// Side vertical-pan zones (normalized)

// Right-side: [ 40% | 20% | 20% | 20% ] left → right
const Rect kRS_40_0_40 = Rect.fromLTWH(0.00, 0, 0.40, 1);
const Rect kRS_40_40_20 = Rect.fromLTWH(0.40, 0, 0.20, 1);
const Rect kRS_60_20_20 = Rect.fromLTWH(0.60, 0, 0.20, 1);
const Rect kRS_80_20_20 = Rect.fromLTWH(0.80, 0, 0.20, 1);
@Deprecated('Use kRS_40_0_40')
const Rect kRH_40_0_40 = Rect.fromLTWH(0.00, 0, 0.40, 1);
@Deprecated('Use kRS_40_40_20')
const Rect kRH_40_40_20 = Rect.fromLTWH(0.40, 0, 0.20, 1);
@Deprecated('Use kRS_60_20_20')
const Rect kRH_60_20_20 = Rect.fromLTWH(0.60, 0, 0.20, 1);
@Deprecated('Use kRS_80_20_20')
const Rect kRH_80_20_20 = Rect.fromLTWH(0.80, 0, 0.20, 1);

// Left-side: [ 20% | 20% | 20% | 40% ] left → right
const Rect kLS_0_20_20 = Rect.fromLTWH(0.00, 0, 0.20, 1);
const Rect kLS_20_20_20 = Rect.fromLTWH(0.20, 0, 0.20, 1);
const Rect kLS_40_20_20 = Rect.fromLTWH(0.40, 0, 0.20, 1);
const Rect kLS_60_40_40 = Rect.fromLTWH(0.60, 0, 0.40, 1);
@Deprecated('Use kLS_0_20_20')
const Rect kLH_0_20_20 = Rect.fromLTWH(0.00, 0, 0.20, 1);
@Deprecated('Use kLS_20_20_20')
const Rect kLH_20_20_20 = Rect.fromLTWH(0.20, 0, 0.20, 1);
@Deprecated('Use kLS_40_20_20')
const Rect kLH_40_20_20 = Rect.fromLTWH(0.40, 0, 0.20, 1);
@Deprecated('Use kLS_60_40_40')
const Rect kLH_60_40_40 = Rect.fromLTWH(0.60, 0, 0.40, 1);

GestureRegion r(
  Rect rect,
  GestureAction action,
) =>
    GestureRegion(
      normalizedRect: rect,
      action: action,
    );
