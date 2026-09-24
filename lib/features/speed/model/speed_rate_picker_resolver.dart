import 'package:iris/features/meta_settings/meta_settings_module.dart';
import 'package:iris/features/speed/model/enum/speed_rate_picker_mode.dart';
import 'package:iris/models/store/app_state.dart';

/// Resolves the effective speed-picker mode.
///
/// Metadata gate OFF (or module not ready) degrades to [SpeedRatePickerMode
/// .list]: the frozen legacy path keeps its flat 0.1 list and never reads the
/// `speed.rateMode` row. Gate ON honours the persisted choice, whose AppState
/// default is [SpeedRatePickerMode.dualWheel].
SpeedRatePickerMode resolveSpeedRatePickerMode(
  AppState state, {
  required bool metadataEnabled,
}) {
  if (!metadataEnabled || !MetaSettingsModule.ready) {
    return SpeedRatePickerMode.list;
  }
  return state.speedRatePickerMode;
}
