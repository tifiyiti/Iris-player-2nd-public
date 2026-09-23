import 'package:iris/models/store/app_state.dart';

/// Which scrubber occupies the circle-slider slot of the landscape control bar.
enum PhoneScrubberSlot { oneHanded, legacyCircleSlider }

/// Resolves the scrubber slot from user settings.
///
/// Ring dial ships metadata-driven only: the legacy persist path is frozen,
/// so a stale `dial` selection read from the legacy blob (metadata gate off)
/// degrades to the classic circle slider instead of rendering the new dial.
///
/// The retired designs (arc/timeLens/snake — requirement #6) degrade to the
/// legacy circle slider as well, in every mode: load-time normalization
/// already folds them into `classic`, and this is the runtime belt-and-braces
/// so a stale value can never bring the dead views back.
PhoneScrubberSlot resolveScrubberSlot({
  required PhoneOneHandedScrubberKind kind,
  required bool metadataEnabled,
}) {
  // The classic circle slider is never a one-handed scrubber — it IS the
  // "simple circle arc" option, always rendered as the legacy circle slider.
  if (kind == PhoneOneHandedScrubberKind.classic) {
    return PhoneScrubberSlot.legacyCircleSlider;
  }
  if (kind == PhoneOneHandedScrubberKind.dial && !metadataEnabled) {
    return PhoneScrubberSlot.legacyCircleSlider;
  }
  // ignore: deprecated_member_use_from_same_package
  if (kind == PhoneOneHandedScrubberKind.arc ||
      // ignore: deprecated_member_use_from_same_package
      kind == PhoneOneHandedScrubberKind.timeLens ||
      // ignore: deprecated_member_use_from_same_package
      kind == PhoneOneHandedScrubberKind.snake) {
    return PhoneScrubberSlot.legacyCircleSlider;
  }
  return PhoneScrubberSlot.oneHanded;
}
