import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/models/store/gesture_region.dart';
import 'package:iris/pages/player/overlays/gesture_region_editor/gesture_settings_dialog.dart';

Map<ScreenOrientation, String> screenOrientationLabelsMap(AppLocalizations t) {
  return {
    ScreenOrientation.device: t.device,
    ScreenOrientation.landscape: t.landscape,
    ScreenOrientation.portrait: t.portrait,
  };
}

Map<PhoneLandscapeSliderType, String> phoneLandscapeSliderTypeLabelsMap(AppLocalizations t) {
  return {
    PhoneLandscapeSliderType.normal: t.ph_use_normal_slider,
    PhoneLandscapeSliderType.circleRight: t.ph_use_circle_slider_right,
    PhoneLandscapeSliderType.circleLeft: t.ph_use_circle_slider_left,
  };
}

Map<CircleSliderCenterAction, String> circleSliderCenterActionLabelsMap(AppLocalizations t) {
  return {
    CircleSliderCenterAction.none: t.circle_slider_center_none,
    CircleSliderCenterAction.toggleControls: t.circle_slider_center_toggle_controls,
    CircleSliderCenterAction.togglePlayPause: t.circle_slider_center_toggle_play_pause,
    CircleSliderCenterAction.switchControlGroup: t.circle_slider_center_switch_group,
  };
}

Map<LandscapeGestureProfile, String> landscapeGestureProfileLabels(AppLocalizations t) => {
      LandscapeGestureProfile.classic: t.gesture_profile_classic,
      LandscapeGestureProfile.region: t.gesture_profile_region,
      LandscapeGestureProfile.rightSide: t.gesture_profile_right_hand,
      LandscapeGestureProfile.leftSide: t.gesture_profile_left_hand,
      LandscapeGestureProfile.rightHand: t.gesture_profile_right_hand,
      LandscapeGestureProfile.leftHand: t.gesture_profile_left_hand,
      LandscapeGestureProfile.tagPlay: t.gesture_profile_tag_play,
    };

Map<PortraitGestureProfile, String> portraitGestureProfileLabels(AppLocalizations t) => {
      PortraitGestureProfile.classic: t.gesture_profile_classic,
      PortraitGestureProfile.region: t.gesture_profile_region,
      PortraitGestureProfile.tagPlay: t.gesture_profile_tag_play,
    };

Map<String, String> gestureLayoutProfileLabelsMap(AppLocalizations t) {
  return {
    kLayoutRegion: t.gesture_profile_default,
    kLayoutRegionRightSide: t.gesture_profile_right_hand,
    kLayoutRegionLeftSide: t.gesture_profile_left_hand,
  };
}

Map<GestureProfile, String> gestureLayoutEnumProfileLabelsMap(AppLocalizations t) {
  return {
    GestureProfile.defaultProfile: t.gesture_profile_default,
    GestureProfile.rightSide: t.gesture_profile_right_hand,
    GestureProfile.leftSide: t.gesture_profile_left_hand,
    // ignore: deprecated_member_use
    GestureProfile.rightHand: t.gesture_profile_right_hand,
    // ignore: deprecated_member_use
    GestureProfile.leftHand: t.gesture_profile_left_hand,
    GestureProfile.tagPlay: t.gesture_profile_tag_play,
  };
}

Map<GestureIntent, String> gestureIntentLabelsMap(AppLocalizations t) {
  return {
    GestureIntent.tap: t.gesture_intent_tap,
    GestureIntent.doubleTap: t.gesture_intent_double_tap,
    GestureIntent.longPress: t.gesture_intent_long_press,
    GestureIntent.longPressPanHorizontal: t.gesture_intent_long_press_pan_horizontal,
    GestureIntent.longPressPanVertical: t.gesture_intent_long_press_pan_vertical,
    GestureIntent.panHorizontal: t.gesture_intent_pan_horizontal,
    GestureIntent.panVertical: t.gesture_intent_pan_vertical,
    GestureIntent.hover: t.gesture_intent_hover,
  };
}

Map<GestureActionType, String> gestureActionTypeLabelsMap(AppLocalizations t) {
  return {
    GestureActionType.none: t.gesture_action_none,

    // Playback
    GestureActionType.playPause: t.gesture_action_play_pause,
    GestureActionType.play: t.gesture_action_play,
    GestureActionType.pause: t.gesture_action_pause,
    GestureActionType.toggleControls: t.gesture_action_toggle_controls,

    // Seeking
    GestureActionType.adjustSeekStep: t.gesture_action_adjust_seek_step,
    GestureActionType.seekForward: t.gesture_action_seek_forward,
    GestureActionType.seekBackward: t.gesture_action_seek_backward,
    GestureActionType.seekTo: t.gesture_action_seek_to,

    // Speed
    GestureActionType.activateTransientSpeed: t.gesture_action_activate_transient_speed,
    GestureActionType.updateTransientSpeed: t.gesture_action_update_transient_speed,
    GestureActionType.deactivateTransientSpeed: t.gesture_action_deactivate_transient_speed,

    GestureActionType.showPlaybackRateSelector: t.gesture_action_show_playback_rate_selector,
    GestureActionType.updatePlaybackRateFromSelector: t.gesture_action_update_playback_rate_from_selector,

    // UI
    GestureActionType.showProgress: t.gesture_action_show_progress,
    GestureActionType.toggleFullscreen: t.gesture_action_toggle_fullscreen,

    // Tag play
    GestureActionType.openTagPlaySheet: t.gesture_action_open_tag_play_sheet,

    // System
    GestureActionType.adjustVolume: t.gesture_action_adjust_volume,
    GestureActionType.adjustBrightness: t.gesture_action_adjust_brightness,
  };
}

Map<GestureIntentType, String> gestureIntentTypeLabelsMap(AppLocalizations t) {
  return {
    GestureIntentType.tap: t.gesture_intent_tap,
    GestureIntentType.doubleTap: t.gesture_intent_double_tap,
    GestureIntentType.longPress: t.gesture_intent_long_press,
    GestureIntentType.panVertical: t.gesture_intent_pan_vertical,
  };
}

/*
 The core rule

 Maps from enum → localized string belong to the UI layer, not to widgets.

 They are:

 UI-specific

 localization-dependent

 pure (no side effects)

 So the goal is:

 one source of truth

 no dependency leaks

 no over-abstraction

 Why this is the right level of abstraction
 ✔ One definition
 ✔ No duplication
 ✔ UI-only dependency
 ✔ Localization-safe
 ✔ Easy to extend

 You’ve created:

 a single concept: “How enums are presented to users”

 That’s a real abstraction, not ceremony.

 Alternative (acceptable, but less flexible)

 If you want even less indirection, you can do:

 extension CircleSliderCenterActionLabel on CircleSliderCenterAction {
 String label(AppLocalizations t) {
 switch (this) {
 case CircleSliderCenterAction.none:
 return t.circle_slider_center_none;
 case CircleSliderCenterAction.toggleControls:
 return t.circle_slider_center_toggle_controls;
 case CircleSliderCenterAction.togglePlayPause:
 return t.circle_slider_center_toggle_play_pause;
 }
 }
 }


 Trade-off:

 ✔ slightly cleaner call site

 ❌ enum now depends on UI localization

 Use this only if you accept that coupling.

 Final recommendation

 👉 Use UI-level mapper functions in a shared file
 👉 Keep enums pure
 👉 Keep localization out of widgets
 👉 Avoid “clever” abstractions

 This solution scales cleanly when:

 you add icons

 you add descriptions

 you add platform-specific labels

 */
