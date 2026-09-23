import 'package:iris/store/use_app_store.dart';

/// Feature gate for desktop drag-and-drop playback (tag_play pattern).
///
/// The scenario-override drop path is entirely ABSENT while the metadata-driven
/// stack is off: the legacy `getLocalPlayQueue` handling in `onDragDone` runs
/// byte-for-byte. Only when the whole chain — no legacy storage persistence,
/// metadata settings and scenario-driven playback — is active does a drop route
/// through [DragDropPlayHandler].
abstract final class DragDropGate {
  static bool get enabled =>
      !useAppStore().state.useLegacyStoragePersistence &&
      useAppStore().state.useMetadataSettings &&
      useAppStore().state.useScenarioDrivenPlayback;
}
