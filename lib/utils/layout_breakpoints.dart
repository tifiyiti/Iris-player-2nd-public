import 'package:flutter/material.dart';

const double kMobileBreakpoint = 640.0;
const double kTabletBreakpoint = 1024.0;

bool isMobileWidthLayout(BuildContext context) => MediaQuery.sizeOf(context).width < kMobileBreakpoint;

bool isTabletWidthLayout(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  return w >= kMobileBreakpoint && w < kTabletBreakpoint;
}

bool isDesktopWidthLayout(BuildContext context) => MediaQuery.sizeOf(context).width >= kTabletBreakpoint;
