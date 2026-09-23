import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/meta_settings/meta_settings_module.dart';
import 'package:iris/features/osd/engine/osd_texts.dart';
import 'package:iris/features/osd/engine/show_player_osd.dart';
import 'package:iris/features/windows/desktop_keyboard/view/shortcut_hints.dart';
import 'package:iris/models/store/video_display_mode.dart';
import 'package:iris/pages/player/control_bar/control_bar_widgets/control_bar_constants.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/platform.dart';
import 'package:iris/widgets/a11y_tooltip.dart';

class FitButton extends HookWidget {
  const FitButton({
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
    final app = useAppStore().select(
        context,
        (s) => (
              s.fit,
              s.useMetadataSettings,
              s.desktopDisplayMode,
              s.mobileDisplayMode,
            ));
    final gateOn = app.$2 && MetaSettingsModule.ready;
    final scheme = useEffectiveKeyboardScheme(context);

    // Metadata era: per-platform display mode drives label/icon/cycle.
    // Legacy era: the classic 4-way BoxFit cycle, untouched.
    final (String modeLabel, IconData iconData) = gateOn
        ? _metaDescriptor(app.$3, app.$4, t)
        : _legacyDescriptor(app.$1, t);

    return a11yTooltipIconButton(
      context: context,
      tooltip:
          '${t.video_zoom}: $modeLabel ( ${shortcutHintLabelFor(ShortcutHintKind.fit, scheme)} )',
      icon: Icon(
        iconData,
        size: kIconSizeSecondary,
        color: color,
      ),
      onPressed: () async {
        showControl();
        if (gateOn) {
          await useAppStore().cycleVideoDisplayMode();
          // Transient centered feedback after the change (PotPlayer parity).
          final app = useAppStore().state;
          showPlayerOsd(OsdTexts.videoDisplayMode(
              isMobilePlatform
                  ? mobileVideoDisplayModeLabel(app.mobileDisplayMode, t)
                  : desktopVideoDisplayModeLabel(app.desktopDisplayMode, t),
              t));
        } else {
          useAppStore().toggleFit();
        }
      },
      style: ButtonStyle(overlayColor: overlayColor),
    );
  }

  (String, IconData) _legacyDescriptor(BoxFit fit, AppLocalizations t) {
    return (
      fit == BoxFit.contain
          ? t.fit
          : fit == BoxFit.fill
              ? t.stretch
              : fit == BoxFit.cover
                  ? t.crop
                  : '100%',
      fit == BoxFit.contain
          ? Icons.fit_screen_rounded
          : fit == BoxFit.fill
              ? Icons.aspect_ratio_rounded
              : fit == BoxFit.cover
                  ? Icons.crop_landscape_rounded
                  : Icons.crop_free_rounded,
    );
  }

  (String, IconData) _metaDescriptor(
    DesktopVideoDisplayMode desktopMode,
    MobileVideoDisplayMode mobileMode,
    dynamic t,
  ) {
    if (isMobilePlatform) {
      return switch (mobileMode) {
        MobileVideoDisplayMode.contain => (t.fit, Icons.fit_screen_rounded),
        MobileVideoDisplayMode.fill => (t.stretch, Icons.aspect_ratio_rounded),
        MobileVideoDisplayMode.cover => (
            t.crop,
            Icons.crop_landscape_rounded
          ),
      };
    }
    return switch (desktopMode) {
      DesktopVideoDisplayMode.contain => (t.fit, Icons.fit_screen_rounded),
      DesktopVideoDisplayMode.fill => (t.stretch, Icons.aspect_ratio_rounded),
      DesktopVideoDisplayMode.cover => (t.crop, Icons.crop_landscape_rounded),
      DesktopVideoDisplayMode.adaptiveOriginal => (
          t.disp_adaptive,
          Icons.crop_free_rounded,
        ),
      DesktopVideoDisplayMode.forcedOriginal => (
          t.disp_forced,
          Icons.filter_none_rounded,
        ),
    };
  }
}
