import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:iris/utils/logger.dart';
final areaKeyLog = AreaKeyLog(LogKeys.legacyUtil);

ValueNotifier<double?> useVolume(bool isGesture) {
  final volume = useState<double?>(null);

  useEffect(() {
    try {
      () async {
        if (!isGesture) return;
        volume.value = await FlutterVolumeController.getVolume();
      }();
    } catch (e) {
      areaKeyLog.e('Error getting volume: $e');
    }
    return () {
      volume.value = null;
    };
  }, [isGesture]);

  useEffect(() {
    try {
      if (volume.value != null && isGesture) {
        FlutterVolumeController.setVolume(volume.value!);
      }
    } catch (e) {
      areaKeyLog.e('Error setting volume: $e');
    }
    return;
  }, [volume.value]);

  return volume;
}
