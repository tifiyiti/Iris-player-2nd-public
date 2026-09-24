import 'package:flutter/material.dart';
import 'package:iris/features/meta_settings/meta_settings_module.dart';
import 'package:iris/features/speed/model/enum/speed_rate_picker_mode.dart';
import 'package:iris/features/speed/model/speed_rate_picker_resolver.dart';
import 'package:iris/features/speed/model/speed_rate_scale_math.dart';
import 'package:iris/features/speed/view/rate_picker_card.dart';
import 'package:iris/features/speed/view/rate_slider_sheet.dart';
import 'package:iris/features/speed/view/rate_wheel_dialog.dart';
import 'package:iris/globals.dart' show speedStops;
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';

/// The legacy flat 0.1 list, in the same draggable card as the other shapes.
Future<void> showRateDialog(BuildContext context) =>
    showDraggableRateCard(context, const RateDialog());

/// Metadata-aware speed picker used by the more menu and the control-bar RATE
/// button. Gate OFF, or `list`, falls back to the legacy flat list dialog so
/// the frozen legacy behavior is unchanged; the other `speed.rateMode` values
/// route to their own shape.
Future<void> showRatePickerDialog(BuildContext context) {
  final store = useAppStore();
  final SpeedRatePickerMode mode = resolveSpeedRatePickerMode(
    store.state,
    metadataEnabled:
        store.state.useMetadataSettings && MetaSettingsModule.ready,
  );
  return switch (mode) {
    SpeedRatePickerMode.dualWheel => showRateWheelDialog(context),
    SpeedRatePickerMode.slider => showRateSliderSheet(context),
    SpeedRatePickerMode.list => showRateDialog(context),
  };
}

/// Flat 100-item list, kept for users who prefer the old long menu.
///
/// A tap APPLIES and closes — the long-standing behaviour — which is why this
/// shape offers Cancel alone rather than the card's usual Save.
class RateDialog extends StatelessWidget {
  const RateDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    return RatePickerCard(
      actionsBuilder: (BuildContext context) => <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.cancel),
        ),
      ],
      buildContent: (BuildContext context, RatePickerHandles handles) =>
          RadioGroup<double>(
        groupValue: handles.current,
        onChanged: (double? value) {
          if (value != null) handles.apply(value);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: speedStops
              .map(
                (double item) => ListTile(
                  title: Text(t.rate_value(formatSpeedLabel(item))),
                  leading: Radio<double>(value: item),
                  onTap: () => handles.apply(item),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}
