import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/scenario_playback/playback/playback_provider_registry.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';
import 'package:iris/features/windows/desktop_keyboard/view/shortcut_hints.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/pages/player/control_bar/control_bar_widgets/control_bar_constants.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/a11y_tooltip.dart';

class RepeatButton extends HookWidget {
  const RepeatButton({
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
    final app = useAppStore();
    final useScenario = app.select(
        context, (s) => !s.useLegacyStoragePersistence && s.useScenarioDrivenPlayback);
    final scenarioRepeat =
        usePlaybackScenarioStore().select(context, (s) => s.activeScenarioRepeat);
    final repeat = useScenario ? scenarioRepeat : app.select(context, (s) => s.repeat);
    final scheme = useEffectiveKeyboardScheme(context);

    return a11yTooltipIconButton(
      context: context,
      tooltip:
          '${repeat == Repeat.one ? t.repeat_one : repeat == Repeat.all ? t.repeat_all : t.repeat_none} ( ${shortcutHintLabelFor(ShortcutHintKind.repeat, scheme)} )',
      icon: Icon(
        repeat == Repeat.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
        size: kIconSizeSecondary,
        color: repeat == Repeat.none ? color?.withAlpha(153) : color,
      ),
      onPressed: () {
        showControl();
        PlaybackProviderRegistry.toggleRepeat();
      },
      style: ButtonStyle(overlayColor: overlayColor),
    );
  }
}
