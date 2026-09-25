import 'package:iris/features/meta_settings/meta_settings_module.dart';
import 'package:iris/features/speed/model/enum/speed_rate_picker_mode.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/utils/platform.dart';

/// Resolves the effective speed-picker mode.
///
/// Metadata gate OFF (or module not ready) degrades to [SpeedRatePickerMode
/// .list]: the frozen legacy path keeps its flat 0.1 list and never reads the
/// `speed.rateMode` row. Gate ON honours the persisted choice, whose AppState
/// default is [SpeedRatePickerMode.dualWheel] — subject to
/// [coerceSpeedRatePickerMode].
SpeedRatePickerMode resolveSpeedRatePickerMode(
  AppState state, {
  required bool metadataEnabled,
}) {
  if (!metadataEnabled || !MetaSettingsModule.ready) {
    return SpeedRatePickerMode.list;
  }
  return coerceSpeedRatePickerMode(state.speedRatePickerMode);
}

/// The modes the CURRENT platform actually offers.
///
/// The wheel is a touch metaphor — spinning it with a mouse gives no keyboard
/// stepping and no click-to-pick — so desktop does not offer it at all rather
/// than offering a picker nobody can drive.
List<SpeedRatePickerMode> speedRatePickerChoices() => isMobilePlatform
    ? SpeedRatePickerMode.values
    : SpeedRatePickerMode.values
        .where((SpeedRatePickerMode m) => m != SpeedRatePickerMode.dualWheel)
        .toList(growable: false);

/// Downgrades a mode the current platform does not offer.
///
/// Desktop never shows the wheel, so a stored `dualWheel` — set on a phone, or
/// carried in by a settings transfer — becomes the slider instead of opening a
/// picker the platform does not offer.
SpeedRatePickerMode coerceSpeedRatePickerMode(SpeedRatePickerMode mode) =>
    (!isMobilePlatform && mode == SpeedRatePickerMode.dualWheel)
        ? SpeedRatePickerMode.slider
        : mode;
