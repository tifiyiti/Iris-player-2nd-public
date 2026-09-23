import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_player_ui_store.dart';

void useOrientation() {
  final context = useContext();
  final orientation = useAppStore().select(context, (state) => state.runtimeOrientation);

  final aspectRatio = usePlayerUiStore().select(context, (state) => state.aspectRatio);

  setOrientation(ScreenOrientation orientation, double? aspect) {
    if (Platform.isAndroid || Platform.isIOS) {
      switch (orientation) {
        case ScreenOrientation.device:
          SystemChrome.setPreferredOrientations([]);
          break;
        case ScreenOrientation.landscape:
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
          break;
        case ScreenOrientation.portrait:
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
          ]);
          break;
      }
    }
  }

  useEffect(() {
    setOrientation(orientation, aspectRatio);
    return () => SystemChrome.setPreferredOrientations([]);
  }, []);

  useEffect(() {
    setOrientation(orientation, aspectRatio);
    return;
  }, [orientation, aspectRatio]);
}
