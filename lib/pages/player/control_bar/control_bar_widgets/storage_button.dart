import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/windows/desktop_keyboard/view/shortcut_hints.dart';
import 'package:iris/pages/player/control_bar/control_bar_widgets/control_bar_constants.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/a11y_tooltip.dart';
import 'package:iris/widgets/popup.dart';
import 'package:iris/widgets/popups/storages/db/storages_db.dart';
import 'package:iris/widgets/popups/storages/storages.dart';

class StorageButton extends HookWidget {
  const StorageButton({
    super.key,
    required this.showControlForHover,
    this.color,
    this.overlayColor,
  });

  final Future<void> Function(Future<void>) showControlForHover;
  final Color? color;
  final WidgetStateProperty<Color?>? overlayColor;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final useLegacy = useAppStore().select(context, (s) => s.useLegacyStoragePersistence);
    final popupDirection = useAppStore().select(context, (s) => s.defaultPopupDirection);
    final scheme = useEffectiveKeyboardScheme(context);

    return a11yTooltipIconButton(
      context: context,
      tooltip: '${t.storage} ( ${shortcutHintLabelFor(ShortcutHintKind.storage, scheme)} )',
      icon: Icon(Icons.storage_rounded, size: kIconSizeSmall, color: color),
      onPressed: () {
        showControlForHover(
          showPopup(
            context: context,
            child: useLegacy ? const Storages() : const StoragesDb(),
            direction: popupDirection,
          ),
        );
      },
      style: ButtonStyle(overlayColor: overlayColor),
    );
  }
}
