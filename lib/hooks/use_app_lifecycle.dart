import 'dart:ui';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/models/player.dart';
import 'package:iris/utils/logger.dart';
import 'package:provider/provider.dart';
final areaKeyLog = AreaKeyLog(LogKeys.legacyMain);

void useAppLifecycle() {
  final context = useContext();

  AppLifecycleState? appLifecycleState = useAppLifecycleState();

  useEffect(() {
    try {
      if (appLifecycleState == AppLifecycleState.paused) {
        areaKeyLog.i('App lifecycle state: paused');
        context.read<MediaPlayer>().saveProgress();
      }
    } catch (e) {
      areaKeyLog.e('App lifecycle state error: $e');
    }
    return;
  }, [appLifecycleState]);
}
