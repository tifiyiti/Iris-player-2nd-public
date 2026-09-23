import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/pages/player/control_bar/control_bar_widgets/control_bar_constants.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/a11y_tooltip.dart';

class RotateButton extends HookWidget {
  const RotateButton({
    super.key,
    required this.showControl,
    this.color,
    this.overlayColor,
  });

  final void Function() showControl;
  final Color? color;
  final WidgetStateProperty<Color?>? overlayColor;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);

    return a11yTooltipIconButton(
      context: context,
      tooltip: t.screen_rotation,
      icon: Icon(Icons.screen_rotation, size: kIconSizeSecondary, color: color),
      onPressed: () {
        showControl();
        final cur = MediaQuery.of(context).orientation;
        if (cur == Orientation.portrait) {
          useAppStore().updateRuntimeOrientation(ScreenOrientation.landscape);
        } else {
          useAppStore().updateRuntimeOrientation(ScreenOrientation.portrait);
        }
      },
      style: ButtonStyle(overlayColor: overlayColor),
    );
  }
}
