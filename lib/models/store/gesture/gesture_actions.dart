import 'package:iris/models/store/gesture_region.dart';

// Short action constructors (pure convenience)
const none = GestureAction(type: GestureActionType.none);

// ── Tap / Playback
const toggle = GestureAction(type: GestureActionType.toggleControls);
const playPause = GestureAction(type: GestureActionType.playPause);

// ── Seeking
const seekF = GestureAction(type: GestureActionType.seekForward);
const seekB = GestureAction(type: GestureActionType.seekBackward);
const seekTo = GestureAction(type: GestureActionType.seekTo);
const adjustSeekStep = GestureAction(type: GestureActionType.adjustSeekStep);

// ── Volume / Brightness
const bright = GestureAction(type: GestureActionType.adjustBrightness);
const volume = GestureAction(type: GestureActionType.adjustVolume);

// ── Speed
const speedActivate = GestureAction(type: GestureActionType.activateTransientSpeed);
const speedUpdate = GestureAction(type: GestureActionType.updateTransientSpeed);

const showRate = GestureAction(type: GestureActionType.showPlaybackRateSelector);
const updateRate = GestureAction(type: GestureActionType.updatePlaybackRateFromSelector);

// ── Tag play
const openTags = GestureAction(type: GestureActionType.openTagPlaySheet);
