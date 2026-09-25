import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';
import 'package:iris/features/windows/desktop_keyboard/view/shortcut_hints.dart';
import 'package:iris/pages/player/control_bar/control_bar_layout/control_bar_slot_actions.dart';
import 'package:iris/pages/player/control_bar/control_bar_widgets/control_bar_constants.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/a11y_tooltip.dart';

class ShuffleButton extends HookWidget {
  const ShuffleButton({super.key, required this.showControl, this.color, this.overlayColor});

  final void Function() showControl;
  final Color? color;
  final WidgetStateProperty<Color?>? overlayColor;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final app = useAppStore();
    final useScenarioDriven = app.select(
      context,
      (s) => !s.useLegacyStoragePersistence && s.useScenarioDrivenPlayback,
    );
    final bg = useBackgroundPlaybackStore();
    // While the controls target 副音 the shuffle shown/toggled is the bg
    // queue's own (fg repeat/shuffle are stored separately per runtime).
    final bgIsControl = bg.select(context, (s) => s.bgOwnsControls);
    final fgShuffle = useScenarioDriven
        ? usePlaybackScenarioStore().select(context, (s) => s.activeScenarioShuffled)
        : app.select(context, (s) => s.shuffle);
    final shuffle =
        bgIsControl ? bg.select(context, (s) => s.shuffle) : fgShuffle;
    final scheme = useEffectiveKeyboardScheme(context);

    return a11yTooltipIconButton(
      context: context,
      tooltip:
          '${t.shuffle}: ${shuffle ? t.on : t.off} ( ${shortcutHintLabelFor(ShortcutHintKind.shuffle, scheme)} )',
      icon: Icon(
        Icons.shuffle_rounded,
        size: kIconSizeSecondary,
        color: shuffle ? color : color?.withAlpha(153),
      ),
      onPressed: () {
        showControl();
        // ignore: discarded_futures
        toggleShuffleFromControlBar(context);
      },
      style: ButtonStyle(overlayColor: overlayColor),
    );
  }
}
