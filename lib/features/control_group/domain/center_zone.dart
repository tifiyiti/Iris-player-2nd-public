import 'package:flutter/widgets.dart' show Offset;
import 'package:iris/models/store/app_state.dart';
import 'package:iris/utils/platform.dart';

/// Resolves the action bound to one center sector (see [CenterZone]).
///
/// Phones honor the four configured sector actions. Desktop keeps the legacy
/// all-[CircleSliderCenterAction.toggleControls] center unless
/// [AppState.desktopCenterZonePhoneMode] opts into the phone layout, so a
/// desktop user who never touches the setting sees the old behavior.
///
/// [isMobileOverride] is a test seam for `isMobilePlatform`.
CircleSliderCenterAction resolveCenterZoneAction(
  AppState state,
  CenterZone zone, {
  bool? isMobileOverride,
}) {
  final bool phone = isMobileOverride ?? isMobilePlatform;
  if (!phone && !state.desktopCenterZonePhoneMode) {
    return CircleSliderCenterAction.toggleControls;
  }
  return switch (zone) {
    CenterZone.inward => state.centerZoneInwardAction,
    CenterZone.outward => state.centerZoneOutwardAction,
    CenterZone.top => state.centerZoneTopAction,
    CenterZone.bottom => state.centerZoneBottomAction,
  };
}

/// Classifies a pointer inside the center hit circle into one of the four
/// sectors split by the faint 45° X.
///
/// The X boundaries are the diagonals, so the sector is decided by comparing
/// |dx| and |dy|: a more-vertical pointer is top/bottom, otherwise left/right.
/// [inwardOnLeft] tells which horizontal side faces the screen centre.
CenterZone centerZoneForOffset(
  Offset local,
  Offset center, {
  required bool inwardOnLeft,
}) {
  final double dx = local.dx - center.dx;
  final double dy = local.dy - center.dy;
  if (dy.abs() > dx.abs()) {
    return dy < 0 ? CenterZone.top : CenterZone.bottom;
  }
  final bool left = dx < 0;
  return left == inwardOnLeft ? CenterZone.inward : CenterZone.outward;
}
