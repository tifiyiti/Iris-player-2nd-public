import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/globals.dart' show rateMenuKeyNotifier, speedStops;
import 'package:iris/hooks/use_published_global_key.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/a11y_tooltip.dart' show kA11yTooltipGate;

class RateButton extends HookWidget {
  const RateButton({
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
    final rate = useAppStore().select(context, (s) => s.rate);
    // Per-mount key (see `usePublishedGlobalKey`): never a shared object.
    final GlobalKey<PopupMenuButtonState> menuKey =
        usePublishedGlobalKey(rateMenuKeyNotifier);
    // Shared a11y gate (semanticsEnabled || accessibleNavigation) — the
    // MediaQuery-only check never engaged under NVDA/UIA on Windows.
    final a11yActive = useValueListenable(kA11yTooltipGate);

    return PopupMenuButton(
      key: menuKey,
      constraints: const BoxConstraints(minWidth: 0),
      itemBuilder: (context) => speedStops
          .map(
            (item) => PopupMenuItem(
              child: Text(
                '${item}X',
                style: TextStyle(
                  color: item == rate ? Theme.of(context).colorScheme.primary : null,
                  fontWeight: item == rate ? FontWeight.bold : FontWeight.w100,
                ),
              ),
              onTap: () {
                showControl();
                useAppStore().updateRate(item);
              },
            ),
          )
          .toList(),
      child: Semantics(
        container: true,
        child: Tooltip(
          message: t.playback_speed,
          triggerMode: a11yActive ? TooltipTriggerMode.tap : null,
          child: TextButton(
            onPressed: () => menuKey.currentState?.showButtonMenu(),
            style: ButtonStyle(overlayColor: overlayColor),
            child: Text('${rate}X',
                style: TextStyle(fontWeight: FontWeight.bold, color: color)),
          ),
        ),
      ),
    );
  }
}
