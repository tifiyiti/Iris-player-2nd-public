import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/features/meta_settings/meta_settings_module.dart';
import 'package:iris/features/phone/one_handed_scrubber/controller/phone_scrubber_slot.dart';
import 'package:iris/features/phone/one_handed_scrubber/view/phone_one_handed_scrubber.dart';
import 'package:iris/features/windows/desktop_control_bar/controller/resolve_desktop_control_bar_layout.dart';
import 'package:iris/features/windows/desktop_control_bar/view/desktop_stacked_control_layout.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/models/store/phone_landscape_slider_type_helper.dart';
import 'package:iris/pages/player/control_bar/control_bar_layout/circle_slider_layout.dart';
import 'package:iris/pages/player/control_bar/control_bar_layout/control_bar_controls.dart';
import 'package:iris/pages/player/control_bar/control_bar_layout/desktop_control_layout.dart';
import 'package:iris/pages/player/control_bar/control_bar_layout/mobile_control_layout.dart';
import 'package:iris/pages/player/control_bar/control_bar_layout/tablet_control_layout.dart';
import 'package:iris/pages/player/control_bar/control_bar_widgets/control_bar_constants.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/store/use_scrub_drag_store.dart';
import 'package:iris/utils/layout_breakpoints.dart';
import 'package:iris/utils/platform.dart';
import 'package:provider/provider.dart';

class ControlBar extends HookWidget {
  const ControlBar({
    super.key,
    required this.showControl,
    required this.showControlForHover,
    this.color,
    this.overlayColor,
  });

  final void Function() showControl;
  final Future<void> Function(Future<void> callback) showControlForHover;
  final Color? color;
  final WidgetStateProperty<Color?>? overlayColor;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    final isPlaying = context.select<MediaPlayer, bool>((player) => player.isPlaying);

    final isSeeking = useScrubDragStore().select(context, (state) => state.isScrubbing);

    final displayIsPlaying = useState(isPlaying);

    final PhoneLandscapeSliderType phoneLandscapeSliderType =
        useAppStore().select(context, (state) => state.phoneLandscapeSliderType);
    final PhoneLandscapeUseMode phoneLandscapeUseMode =
        useAppStore().select(context, (state) => state.phoneLandscapeUseMode);
    final circleSliderPanelWidthPercent =
        useAppStore().select(context, (state) => state.circleLandscapePercent);

    final runtimeOrientation = useAppStore().select(context, (state) => state.runtimeOrientation);
    final realOrientation = MediaQuery.of(context).orientation;

    final bool isLandscape = isLandscapeOrientation(
      runtimeOrientation: runtimeOrientation,
      realOrientation: realOrientation,
    );

final bool useCircleSlider = isMobilePlatform &&
        isLandscape &&
        (phoneLandscapeSliderType == PhoneLandscapeSliderType.circleRight ||
            phoneLandscapeSliderType == PhoneLandscapeSliderType.circleLeft);
    final bool useOneHandedScrubber =
        (isDesktop || (isMobilePlatform && isLandscape)) &&
            phoneLandscapeUseMode.usesOneHandedControls;
    final PhoneOneHandedScrubberKind scrubberKind =
        useAppStore().select(context, (state) => state.phoneOneHandedScrubberKind);
    final bool metaSettingsOn =
        useAppStore().select(context, (state) => state.useMetadataSettings);
    // Ring dial ships metadata-driven only; under the frozen legacy path a
    // stale 'dial' selection degrades to the classic circle slider.
    final PhoneScrubberSlot scrubberSlot = resolveScrubberSlot(
      kind: scrubberKind,
      metadataEnabled: metaSettingsOn,
    );
    // Stacked desktop bar ships metadata-driven only; gate OFF keeps the
    // classic one-line arrangement (see features/windows/desktop_control_bar).
    final DesktopControlBarLayout desktopBarLayout =
        resolveDesktopControlBarLayout(
      stored: useAppStore()
          .select(context, (state) => state.desktopControlBarLayout),
      metadataEnabled: metaSettingsOn && MetaSettingsModule.ready,
    );

    final playQueue = usePlayQueueStore().select(context, (state) => state.playQueue);
    final currentIndex = usePlayQueueStore().select(context, (state) => state.currentIndex);

    final FileItem? file = useMemoized(() {
      final index = playQueue.indexWhere((element) => element.index == currentIndex);
      return playQueue.isEmpty || index < 0 ? null : playQueue[index].file;
    }, [playQueue, currentIndex]);

    useEffect(() {
      if (!isSeeking) {
        displayIsPlaying.value = isPlaying;
      }
      return null;
    }, [isPlaying]);

    final scale = useAppStore().select(context, (s) => s.circleSliderScale);
    final quickBarAlign = useBackgroundPlaybackStore()
        .select(context, (s) => s.quickBarAlign);

    final controls = ControlBarControls(
      showControl: showControl,
      showControlForHover: showControlForHover,
      color: color,
      overlayColor: overlayColor,
      file: file,
      circleScale: scale, // 👈 inject here
      quickBarAlign: quickBarAlign,
    );

    Widget selectLinearLayout(double width, ControlBarControls controls) {
      if (width < kMobileBreakpoint) {
        return MobileControlLayout(controls: controls);
      } else if (width < kTabletBreakpoint) {
        return TabletControlLayout(controls: controls);
      } else {
        return desktopBarLayout == DesktopControlBarLayout.stacked
            ? DesktopStackedControlLayout(controls: controls)
            : DesktopControlLayout(controls: controls);
      }
    }

    final Widget layout = useOneHandedScrubber
        ? CircleSliderLayout(
            width: width,
            panelPercent: circleSliderPanelWidthPercent,
            controls: controls,
            showControl: showControl,
            scrubberBuilder:
                (double? availableSpan, double? dialHeightPx) =>
                    scrubberSlot == PhoneScrubberSlot.oneHanded
                        ? PhoneOneHandedScrubber(
                            showControl: showControl,
                            color: color,
                            isLeftHanded: phoneLandscapeUseMode.isLeftHanded,
                            availableSpan: availableSpan,
                            dialHeightPx: dialHeightPx,
                          )
                        : controls.circleSlider,
          )
        : useCircleSlider
        ? CircleSliderLayout(
            width: width,
            panelPercent: circleSliderPanelWidthPercent,
            controls: controls,
            showControl: showControl,
            scrubberBuilder: (double? _, double? __) => controls.circleSlider,
          )
        : selectLinearLayout(width, controls);

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            // transparent → subtle dark → strong dark
            Colors.black.withValues(alpha: kOverlayGradientTopOpacity),
            Colors.black.withValues(alpha: kOverlayGradientMidOpacity),
            Colors.black.withValues(alpha: kOverlayGradientBottomOpacity),
          ],
        ),
      ),
      child: layout,
    );
  }
}
