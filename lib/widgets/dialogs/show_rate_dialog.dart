import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/meta_settings/meta_settings_module.dart';
import 'package:iris/features/speed/model/enum/speed_rate_picker_mode.dart';
import 'package:iris/features/speed/model/speed_rate_picker_resolver.dart';
import 'package:iris/features/speed/view/rate_wheel_dialog.dart';
import 'package:iris/globals.dart' show speedStops;
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';

Future<void> showRateDialog(BuildContext context) async =>
    await showDialog<void>(
      context: context,
      builder: (context) => const RateDialog(),
    );

/// Metadata-aware speed picker used by the more menu and the control-bar RATE
/// button. Gate ON + `dualWheel` opens the alarm-clock wheel dialog; every
/// other case (gate OFF, or `list`) falls back to the legacy flat list dialog
/// so the frozen legacy behavior is unchanged.
Future<void> showRatePickerDialog(BuildContext context) {
  final store = useAppStore();
  final SpeedRatePickerMode mode = resolveSpeedRatePickerMode(
    store.state,
    metadataEnabled:
        store.state.useMetadataSettings && MetaSettingsModule.ready,
  );
  if (mode == SpeedRatePickerMode.dualWheel) {
    return showRateWheelDialog(context);
  }
  return showRateDialog(context);
}

class RateDialog extends HookWidget {
  const RateDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final rate = useAppStore().select(context, (state) => state.rate);

    void updateRate(double? newRate) {
      if (newRate == null) return;
      useAppStore().updateRate(newRate);
      Navigator.pop(context);
    }

    return AlertDialog(
      title: Text(t.playback_speed),
      content: SingleChildScrollView(
        child: RadioGroup<double>(
          groupValue: rate,
          onChanged: updateRate,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: speedStops.map((item) {
              return ListTile(
                title: Text('${item}X'),
                leading: Radio<double>(
                  value: item,
                ),
                onTap: () => updateRate(item),
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
