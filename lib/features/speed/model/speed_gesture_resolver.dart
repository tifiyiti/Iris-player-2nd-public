import 'package:iris/features/meta_settings/meta_settings_module.dart';
import 'package:iris/features/speed/model/enum/speed_gesture_mode.dart';
import 'package:iris/models/store/app_state.dart';

SpeedGestureMode resolveSpeedGestureMode(
  AppState state, {
  required bool metadataEnabled,
}) {
  if (!metadataEnabled || !MetaSettingsModule.ready) {
    return SpeedGestureMode.singleAxis;
  }
  return state.speedGestureMode;
}
