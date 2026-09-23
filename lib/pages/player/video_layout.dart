import 'package:flutter/widgets.dart';

/// Keeps the video surface at a valid size while a desktop window is being
/// resized. A zero-sized Texture can be detached and reattached faster than
/// the Windows accessibility bridge can consume its semantics updates.
Size? retainValidVideoSize(Size candidate, Size? previous) {
  bool isValid(Size value) =>
      value.width.isFinite &&
      value.height.isFinite &&
      value.width > 0 &&
      value.height > 0;

  if (isValid(candidate)) return candidate;
  if (previous != null && isValid(previous)) return previous;
  return null;
}
