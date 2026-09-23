import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';

Future<void> showOrientationDialog(BuildContext context) async => await showDialog<void>(
      context: context,
      builder: (context) => const OrientationDialog(),
    );

class OrientationDialog extends HookWidget {
  const OrientationDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final orientation = useAppStore().select(context, (state) => state.preferredOrientation);

    void updateOrientation(ScreenOrientation? newOrientation) {
      if (newOrientation == null) return;

      useAppStore().updatePreferredOrientation(newOrientation);
      useAppStore().updateRuntimeOrientation(newOrientation);
      Navigator.pop(context);
    }

    final orientationMap = {
      ScreenOrientation.device: t.device,
      ScreenOrientation.landscape: t.landscape,
      ScreenOrientation.portrait: t.portrait,
    };

    return AlertDialog(
      title: Text(t.screen_orientation),
      content: SingleChildScrollView(
        child: RadioGroup<ScreenOrientation>(
          groupValue: orientation,
          onChanged: updateOrientation,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: ScreenOrientation.values.map((e) {
              return ListTile(
                title: Text(orientationMap[e] ?? e.name),
                leading: Radio<ScreenOrientation>(
                  value: e,
                ),
                onTap: () => updateOrientation(e),
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
