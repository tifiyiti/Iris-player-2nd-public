import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/windows/desktop_keyboard/view/shortcut_hints.dart';
import 'package:iris/pages/player/control_bar/volume_slider.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/a11y_tooltip.dart';
import 'package:popover/popover.dart';

Future<void> showVolumePopover(
  BuildContext context,
  void Function() showControl,
) async =>
    showPopover(
      context: context,
      bodyBuilder: (context) => Container(
        padding: EdgeInsets.fromLTRB(8, 0, 16, 0),
        child: VolumeControl(showControl: showControl),
      ),
      direction: PopoverDirection.top,
      width: 240,
      height: 48,
      arrowHeight: 0,
      arrowWidth: 0,
      backgroundColor: Theme.of(context).colorScheme.surface,
      barrierColor: Colors.transparent,
    );

class VolumeControl extends HookWidget {
  const VolumeControl({
    super.key,
    required this.showControl,
    this.showVolumeText = true,
    this.color,
    this.overlayColor,
  });

  final void Function() showControl;
  final bool showVolumeText;
  final Color? color;
  final WidgetStateProperty<Color?>? overlayColor;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final volume = useAppStore().select(context, (state) => state.volume);
    final isMuted = useAppStore().select(context, (state) => state.isMuted);
    final scheme = useEffectiveKeyboardScheme(context);
    return Listener(
      onPointerSignal: (PointerSignalEvent event) async {
        if (event is PointerScrollEvent) {
          if (event.scrollDelta.dy < 0) {
            showControl();
            if (isMuted) {
              await useAppStore().updateVolume(0);
              await useAppStore().updateMute(false);
            } else {
              useAppStore().updateVolume(volume + 2);
            }
          } else {
            showControl();
            useAppStore().updateVolume(volume - 2);
          }
        }
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        textBaseline: TextBaseline.ideographic,
        children: [
          a11yTooltipIconButton(
            context: context,
            tooltip:
                '${isMuted ? t.unmute : t.mute} ( ${shortcutHintLabelFor(ShortcutHintKind.mute, scheme)} )',
            icon: Icon(
              isMuted || volume == 0
                  ? Icons.volume_off_rounded
                  : volume < 50
                      ? Icons.volume_down_rounded
                      : Icons.volume_up_rounded,
              size: 20,
              color: color,
            ),
            onPressed: () {
              showControl();
              if (volume == 0) {
                useAppStore().updateVolume(80);
              } else {
                useAppStore().toggleMute();
              }
            },
            style: ButtonStyle(overlayColor: overlayColor),
          ),
          Expanded(
            child: VolumeSlider(
              showControl: showControl,
              color: color,
            ),
          ),
          if (showVolumeText) const SizedBox(width: 8),
          if (showVolumeText) Text('${volume >= 100 ? '' : '  '}$volume'),
        ],
      ),
    );
  }
}
