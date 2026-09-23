import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/tag_play/playback/tag_play_controller.dart';
import 'package:iris/features/tag_play/store/use_tag_play_store.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';

enum GestureProfile { defaultProfile, rightSide, leftSide, rightHand, leftHand, tagPlay }

enum GestureIntentType { tap, doubleTap, panVertical, longPress }

class GestureSettingsSelection {
  GestureSettingsSelection({
    required this.profile,
    required this.intent,
  });

  final GestureProfile profile;
  final GestureIntentType intent;
}

/// Orientation-aware preview profile. Portrait only has one profile
/// (portrait region); landscape has region/rightSide/leftSide. Tag auto-follow
/// is landscape-only.
GestureProfile _effectivePreviewProfile(
  BuildContext context,
  AppState state,
  bool isLandscape,
) {
  if (!isLandscape) return GestureProfile.defaultProfile;
  // AUTO-FOLLOW: an active tag view temporarily overrides the manual pick (landscape only).
  if (TagPlayGate.viewSwitchingEnabled &&
      useTagPlayStore().state.activeViewTagId != null) {
    return GestureProfile.tagPlay;
  }
  return switch (state.landscapeGestureProfile) {
    LandscapeGestureProfile.classic => GestureProfile.defaultProfile,
    LandscapeGestureProfile.region => GestureProfile.defaultProfile,
    LandscapeGestureProfile.rightSide => GestureProfile.rightSide,
    LandscapeGestureProfile.leftSide => GestureProfile.leftSide,
    LandscapeGestureProfile.rightHand => GestureProfile.rightSide,
    LandscapeGestureProfile.leftHand => GestureProfile.leftSide,
    LandscapeGestureProfile.tagPlay => GestureProfile.tagPlay,
  };
}

List<GestureProfile> _availableProfiles(bool isLandscape) {
  if (!isLandscape) return const [GestureProfile.defaultProfile];
  return const [
    GestureProfile.defaultProfile,
    GestureProfile.rightSide,
    GestureProfile.leftSide,
  ];
}

String _profileLabel(GestureProfile p, t) => switch (p) {
      GestureProfile.defaultProfile => t.guide_profile_default,
      GestureProfile.rightSide => t.guide_profile_right,
      GestureProfile.leftSide => t.guide_profile_left,
      GestureProfile.rightHand => t.guide_profile_right,
      GestureProfile.leftHand => t.guide_profile_left,
      GestureProfile.tagPlay => t.guide_action_open_tag,
    };

String _intentLabel(GestureIntentType i, t) => switch (i) {
      GestureIntentType.tap => t.guide_intent_type_tap,
      GestureIntentType.doubleTap => t.guide_intent_type_double_tap,
      GestureIntentType.panVertical => t.guide_intent_type_pan_v,
      GestureIntentType.longPress => t.guide_intent_type_long_press,
    };

/// Shows ONE dialog with radio buttons filtered by orientation.
/// Portrait → only defaultProfile (portrait region); landscape → region/right/left.
/// Defaults to the CURRENTLY EFFECTIVE profile (auto-follow aware) and badges it.
Future<GestureSettingsSelection?> showGestureSettingsDialog(
  BuildContext context, {
  required bool isLandscape,
}) {
  return showDialog<GestureSettingsSelection>(
    context: context,
    builder: (_) => GestureSettingsDialog(isLandscape: isLandscape),
  );
}

class GestureSettingsDialog extends HookWidget {
  const GestureSettingsDialog({super.key, required this.isLandscape});

  final bool isLandscape;

  @override
  Widget build(BuildContext context) {
    final app = useAppStore();
    final effective = useAppStore().select(
      context,
      (s) => _effectivePreviewProfile(context, s, isLandscape),
    );
    final profile = useState<GestureProfile?>(null);
    final selected = profile.value ?? effective;
    final intent = useState(GestureIntentType.tap);
    final t = getLocalizations(context);

    return AlertDialog(
      title: Text(t.gesture_settings_title),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.gesture_settings_profile,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            RadioGroup<GestureProfile>(
              groupValue: selected,
              onChanged: (v) => profile.value = v!,
              child: Column(
                children: [
                  for (final p in _availableProfiles(isLandscape))
                      RadioListTile<GestureProfile>(
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _profileLabel(p, t),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (p == effective && app.state.useMetadataSettings)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Chip(
                                  label: Text(
                                    TagPlayGate.viewSwitchingEnabled &&
                                            useTagPlayStore()
                                                .state
                                                .activeViewTagId !=
                                                null
                                        ? t.guide_badge_active
                                        : t.guide_badge_current,
                                    style:
                                        Theme.of(context).textTheme.labelSmall,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                ),
                              ),
                          ],
                        ),
                        value: p,
                      ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(t.gesture_settings_intent,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            RadioGroup<GestureIntentType>(
              groupValue: intent.value,
              onChanged: (v) => intent.value = v!,
              child: Column(
                children: [
                  for (final i in GestureIntentType.values)
                    RadioListTile<GestureIntentType>(
                      title: Text(_intentLabel(i, t)),
                      value: i,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(
              context,
              GestureSettingsSelection(
                profile: selected,
                intent: intent.value,
              ),
            );
          },
          child: Text(t.edit),
        ),
      ],
    );
  }
}
