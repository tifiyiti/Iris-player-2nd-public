import 'package:flutter/material.dart';
import 'package:iris/hooks/ui/mappers/enum_localization.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/dialogs/show_enum_radio_dialog.dart';

void showLandscapeGestureSettingDialog(BuildContext context) {
  final t = getLocalizations(context);
  final store = useAppStore();

  showEnumRadioDialog<LandscapeGestureProfile>(
    context: context,
    title: t.landscape_gesture_profile,
    values: LandscapeGestureProfile.values,
    currentValue: store.state.landscapeGestureProfile,
    labelOf: (e) => landscapeGestureProfileLabels(t)[e] ?? e.name,
    onSelected: useAppStore().updateLandscapeGestureProfile,
  );
}

void showPortraitGestureSettingDialog(BuildContext context) {
  final t = getLocalizations(context);
  final store = useAppStore();

  showEnumRadioDialog<PortraitGestureProfile>(
    context: context,
    title: t.portrait_gesture_profile,
    values: PortraitGestureProfile.values,
    currentValue: store.state.portraitGestureProfile,
    labelOf: (e) => portraitGestureProfileLabels(t)[e] ?? e.name,
    onSelected: useAppStore().updatePortraitGestureProfile,
  );
}

/*

Future<void> showCircleSliderCenterActionDialog(BuildContext context) async => await showDialog<void>(
      context: context,
      builder: (context) => const CircleSliderCenterActionDialog(),
    );

/// Dialog for selecting the behavior triggered by tapping
/// the center of the circular playback slider.
///
/// The selection is persisted immediately and applied
/// consistently across playback sessions.
class CircleSliderCenterActionDialog extends HookWidget {
  const CircleSliderCenterActionDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final settingValue = useAppStore().select(context, (state) => state.circleSliderCenterAction);

    void updateChoose(CircleSliderCenterAction? newValue) {
      if (newValue == null) return;

      useAppStore().updateCircleSliderCenterAction(newValue);
      Navigator.pop(context);
    }

    final circleSliderCenterActionLabels = circleSliderCenterActionLabelsMap(t);

    return AlertDialog(
      title: Text(t.screen_orientation),
      content: SingleChildScrollView(
        child: RadioGroup<CircleSliderCenterAction>(
          groupValue: settingValue,
          onChanged: updateChoose,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: CircleSliderCenterAction.values.map((e) {
              return ListTile(
                title: Text(circleSliderCenterActionLabels[e] ?? e.name),
                leading: Radio<CircleSliderCenterAction>(
                  value: e,
                ),
                onTap: () => updateChoose(e),
              );
            }).toList(),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.cancel),
        ),
      ],
    );
  }
}
*/
