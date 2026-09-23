import 'package:flutter/material.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/store/gesture/gesture_actions.dart';
import 'package:iris/models/store/gesture_region.dart';

/// One drawable gesture region of the live guide.
class GuideRegionEntry {
  final Rect normalizedRect;
  final GestureAction action;

  const GuideRegionEntry({
    required this.normalizedRect,
    required this.action,
  });
}

/// A guide page: all regions belonging to one [GestureIntent].
class GuideSection {
  final GestureIntent intent;
  final String title;
  final List<GuideRegionEntry> regions;

  const GuideSection({
    required this.intent,
    required this.title,
    required this.regions,
  });
}

const List<GestureIntent> _kGuideIntentOrder = [
  GestureIntent.doubleTap,
  GestureIntent.tap,
  GestureIntent.longPress,
  GestureIntent.panVertical,
  GestureIntent.panHorizontal,
  GestureIntent.longPressPanVertical,
  GestureIntent.longPressPanHorizontal,
];

String guideIntentTitle(GestureIntent intent, AppLocalizations t) =>
    switch (intent) {
      GestureIntent.tap => t.guide_intent_tap,
      GestureIntent.doubleTap => t.guide_intent_double_tap,
      GestureIntent.longPress => t.guide_intent_long_press,
      GestureIntent.longPressPanHorizontal => t.guide_intent_long_press_pan_h,
      GestureIntent.longPressPanVertical => t.guide_intent_long_press_pan_v,
      GestureIntent.panHorizontal => t.guide_intent_pan_h,
      GestureIntent.panVertical => t.guide_intent_pan_v,
      GestureIntent.hover => t.guide_intent_hover,
    };

/// Flattens a resolved layout map into ordered, drawable guide sections.
///
/// Intents without regions and desktop-only `hover` are dropped so the
/// phone guide never shows empty or irrelevant pages.
List<GuideSection> buildGuideSections(
    Map<GestureIntent, GestureLayout> layouts, AppLocalizations t) {
  final sections = <GuideSection>[];
  for (final intent in _kGuideIntentOrder) {
    final layout = layouts[intent];
    if (layout == null || layout.regions.isEmpty) continue;
    sections.add(GuideSection(
      intent: intent,
      title: guideIntentTitle(intent, t),
      regions: [
        for (final r in layout.regions)
          GuideRegionEntry(
            normalizedRect: r.normalizedRect,
            action: r.action,
          ),
      ],
    ));
  }
  return sections;
}

/// Icon + label + emphasis for one configured action.
class GuideActionDescriptor {
  final IconData icon;
  final String label;

  /// False for `none` — the view renders these muted so users can spot
  /// unconfigured areas worth editing.
  final bool active;

  const GuideActionDescriptor({
    required this.icon,
    required this.label,
    this.active = true,
  });
}

GuideActionDescriptor describeAction(
    GestureAction action, AppLocalizations t) {
  switch (action.type) {
    case GestureActionType.none:
      return GuideActionDescriptor(
        icon: Icons.crop_free,
        label: t.guide_action_none,
        active: false,
      );

    case GestureActionType.playPause:
    case GestureActionType.play:
    case GestureActionType.pause:
      return GuideActionDescriptor(
          icon: Icons.play_arrow, label: t.guide_action_play_pause);
    case GestureActionType.toggleControls:
      return GuideActionDescriptor(
          icon: Icons.visibility, label: t.guide_action_toggle_controls);

    case GestureActionType.seekForward:
      return GuideActionDescriptor(
        icon: Icons.forward_10,
        label: action.duration != null
            ? t.guide_action_seek_forward_secs(
                action.duration!.inSeconds)
            : t.guide_action_seek_forward,
      );
    case GestureActionType.seekBackward:
      return GuideActionDescriptor(
        icon: Icons.replay_10,
        label: action.duration != null
            ? t.guide_action_seek_backward_secs(
                action.duration!.inSeconds)
            : t.guide_action_seek_backward,
      );
    case GestureActionType.seekTo:
      return GuideActionDescriptor(
          icon: Icons.moving, label: t.guide_action_seek_to);
    case GestureActionType.adjustSeekStep:
      return GuideActionDescriptor(
          icon: Icons.linear_scale, label: t.guide_action_adjust_step);

    case GestureActionType.activateTransientSpeed:
      return GuideActionDescriptor(
          icon: Icons.speed, label: t.guide_action_speed_on);
    case GestureActionType.updateTransientSpeed:
      return GuideActionDescriptor(
          icon: Icons.speed, label: t.guide_action_speed_update);
    case GestureActionType.deactivateTransientSpeed:
      return GuideActionDescriptor(
          icon: Icons.speed, label: t.guide_action_speed_off);
    case GestureActionType.showPlaybackRateSelector:
      return GuideActionDescriptor(
          icon: Icons.speed, label: t.guide_action_speed_menu);
    case GestureActionType.updatePlaybackRateFromSelector:
      return GuideActionDescriptor(
          icon: Icons.speed, label: t.guide_action_speed_pick);

    case GestureActionType.showProgress:
      return GuideActionDescriptor(
          icon: Icons.timelapse, label: t.guide_action_show_progress);
    case GestureActionType.toggleFullscreen:
      return GuideActionDescriptor(
          icon: Icons.fullscreen, label: t.guide_action_fullscreen);

    case GestureActionType.openTagPlaySheet:
      return GuideActionDescriptor(
          icon: Icons.style_rounded, label: t.guide_action_open_tag);

    case GestureActionType.adjustVolume:
      return GuideActionDescriptor(
          icon: Icons.volume_up, label: t.guide_action_volume);
    case GestureActionType.adjustBrightness:
      return GuideActionDescriptor(
          icon: Icons.brightness_6, label: t.guide_action_brightness);
  }
}

// Re-exported so the view can reference the same constants without a second
// import path.
const GestureAction kNoneAction = none;
