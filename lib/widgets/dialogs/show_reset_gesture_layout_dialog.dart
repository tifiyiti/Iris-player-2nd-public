import 'package:flutter/material.dart';
import 'package:iris/hooks/ui/mappers/enum_localization.dart';
import 'package:iris/models/store/gesture_region.dart';
import 'package:iris/pages/player/overlays/gesture_region_editor/gesture_settings_dialog.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/dialogs/show_enum_checkbox_dialog.dart';

void showResetGestureLayoutDialog(BuildContext context) {
  final t = getLocalizations(context);

  showGroupedCheckboxDialog(
    context: context,
    title: t.reset_gesture_layout_title,
    groups: [
      CheckboxGroup(
        key: 'profiles',
        title: t.reset_gesture_group_profiles,
        values: [
          GestureProfile.defaultProfile,
          GestureProfile.rightSide,
          GestureProfile.leftSide,
        ],
        initialSelected: {GestureProfile.defaultProfile},
        labelOf: (key) => gestureLayoutEnumProfileLabelsMap(t)[key] ?? key.toString(),
      ),
      CheckboxGroup(
        key: 'intents',
        title: t.reset_gesture_group_intents,
        values: [
          GestureIntentType.tap,
          GestureIntentType.doubleTap,
          GestureIntentType.panVertical,
          GestureIntentType.longPress,
        ],
        labelOf: (e) => gestureIntentTypeLabelsMap(t)[e] ?? e.toString(),
      ),
    ],
    onConfirmed: (result) async {
      final profiles = (result['profiles'] ?? {})
          .cast<GestureProfile>()
          .expand((p) => switch (p) {
                // Default covers both portrait and landscape region.
                GestureProfile.defaultProfile =>
                  [kLayoutRegionPortrait, kLayoutRegion],
                GestureProfile.rightSide => [kLayoutRegionRightSide],
                GestureProfile.leftSide => [kLayoutRegionLeftSide],
                // ignore: deprecated_member_use
                GestureProfile.rightHand => [kLayoutRegionRightSide],
                // ignore: deprecated_member_use
                GestureProfile.leftHand => [kLayoutRegionLeftSide],
                GestureProfile.tagPlay =>
                  [kLayoutRegionPortrait, kLayoutRegion],
              })
          .toSet();

      final intents = (result['intents'] ?? {})
          .cast<GestureIntentType>()
          .map((i) => switch (i) {
                GestureIntentType.tap => GestureIntent.tap,
                GestureIntentType.doubleTap => GestureIntent.doubleTap,
                GestureIntentType.panVertical => GestureIntent.panVertical,
                GestureIntentType.longPress => GestureIntent.longPress,
              })
          .toSet();

      if (profiles.isNotEmpty && intents.isNotEmpty) {
        await useAppStore().resetGestureLayoutsBySelection(
          profileKeys: profiles,
          intents: intents,
        );
      }
    },
  );
}
