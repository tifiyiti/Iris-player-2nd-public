import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/models/store/gesture/gesture_region_layout.dart';
import 'package:iris/store/use_app_store.dart';

/// Reactively resolves the active [GestureMode] for the current frame.
///
/// The verdict is a plain per-build computation, but the three inputs that can
/// decide it ([AppState.useMetadataSettings] plus both gesture profiles) are
/// subscribed via select(). This matters on phones: [AppStore] loads
/// asynchronously, so the first frame sees the gate-OFF default. A memoized
/// verdict (the previous implementation, keyed only on profiles/orientation)
/// stayed `classic` forever because none of its keys changed when the loaded
/// state landed — region gestures only woke up after an orientation flip.
/// With the subscriptions the mode flips to `region` the moment settings
/// arrive or the user toggles the gate.
GestureMode useGestureMode({
  required Orientation orientation,
  required bool isPhone,
}) {
  final context = useContext();
  final app = useAppStore();
  final gate = app.select(context, (s) => s.useMetadataSettings);
  final landscape = app.select(context, (s) => s.landscapeGestureProfile);
  final portrait = app.select(context, (s) => s.portraitGestureProfile);

  return resolveGestureMode(
    state: app.state.copyWith(
      useMetadataSettings: gate,
      landscapeGestureProfile: landscape,
      portraitGestureProfile: portrait,
    ),
    orientation: orientation,
    isPhone: isPhone,
  );
}
