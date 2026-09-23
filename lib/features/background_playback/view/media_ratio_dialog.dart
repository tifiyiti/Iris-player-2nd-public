import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/background_playback/hooks/use_background_volume_context.dart';
import 'package:iris/features/background_playback/model/domain/media_ratio.dart';
import 'package:iris/features/background_playback/model/enum/bg_quick_panel.dart';
import 'package:iris/features/background_playback/model/enum/ratio_scope.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/controls/vertical_value_strip.dart';

/// fg/bg volume-ratio editor (sub_media §5.5).
///
/// Two vertical strips set the foreground and 副音 shares of the shared master
/// volume. A scope switch picks the layer being edited — the global pair or the
/// override for the media playing right now (an empty override falls back to
/// global). Writing follows the "explicit save" preference: ON commits only on
/// Save, OFF applies live and commits when the finger lifts.
///
/// Rendered as a NON-MODAL draggable card by `BgQuickPanelHost` (the old modal
/// dialog dimmed the video); this entry point just toggles that card.
Future<void> showMediaRatioDialog(BuildContext context) async {
  useBackgroundPlaybackStore().toggleQuickPanel(BgQuickPanel.ratio);
}

/// Body of the ratio card (no dialog chrome — the host card supplies the
/// draggable header and close button).
///
/// The strip band deliberately sits OUTSIDE any scroll view: an ancestor
/// `Scrollable` wins the vertical drag arena against the strip's
/// `PanGestureRecognizer`, which is exactly why the old dialog's strips felt
/// unmovable (第 4 轮问题 3).
class MediaRatioPanelContent extends HookWidget {
  const MediaRatioPanelContent({super.key});

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final bg = useBackgroundPlaybackStore();
    final scope = bg.select(context, (s) => s.ratioScope);
    final explicitSave = bg.select(context, (s) => s.ratioExplicitSave);
    final ratioEnabled = bg.select(context, (s) => s.volumeRatioEnabled);
    final globalFg = bg.select(context, (s) => s.fgVolumePercent);
    final globalBg = bg.select(context, (s) => s.bgVolumePercent);
    final volume = useBackgroundVolumeContext(context);
    final fgKey = volume.fgKey;

    // Draft being edited. Seeded from the layer in scope, re-seeded when the
    // scope switches so the strips always show what that layer holds.
    final draftFg = useState(volume.ratio.fgPercent);
    final draftBg = useState(volume.ratio.bgPercent);
    useEffect(() {
      draftFg.value = volume.ratio.fgPercent;
      draftBg.value = volume.ratio.bgPercent;
      return null;
    }, [scope, globalFg, globalBg, volume.ratio]);

    void apply(MediaRatio ratio) {
      unawaited(bg.applyRatio(fgKey: fgKey, ratio: ratio));
    }

    void onFgChanged(int v) {
      draftFg.value = v;
      if (!explicitSave) {
        apply(MediaRatio(fgPercent: v, bgPercent: draftBg.value));
      }
    }

    void onBgChanged(int v) {
      draftBg.value = v;
      if (!explicitSave) {
        apply(MediaRatio(fgPercent: draftFg.value, bgPercent: v));
      }
    }

    void commitDraft() {
      apply(MediaRatio(fgPercent: draftFg.value, bgPercent: draftBg.value));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Preference region — the only scrollable part, so it never competes
        // with the strips below.
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t.bg_volume_ratio_desc,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                Center(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SegmentedButton<RatioScope>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                          value: RatioScope.global,
                          label: Text(t.bg_ratio_scope_global),
                        ),
                        ButtonSegment(
                          value: RatioScope.current,
                          label: Text(t.bg_ratio_scope_current),
                        ),
                      ],
                      selected: {scope},
                      onSelectionChanged: (s) =>
                          unawaited(bg.setRatioScope(s.first)),
                    ),
                  ),
                ),
                if (!explicitSave) ...[
                  const SizedBox(height: 8),
                  Text(
                    t.bg_ratio_live_hint,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
                if (scope == RatioScope.current && fgKey == null) ...[
                  const SizedBox(height: 4),
                  Text(
                    t.bg_ratio_no_current_media,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ],
            ),
          ),
        ),
        // Fixed band, NO scroll ancestor: the strips own their vertical drags.
        SizedBox(
          height: 150,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _RatioStrip(
                  label: t.bg_foreground_volume,
                  value: draftFg.value,
                  accent: Theme.of(context).colorScheme.primary,
                  onChanged: onFgChanged,
                  onChangeEnd: (_) {
                    if (!explicitSave) commitDraft();
                  },
                ),
                const SizedBox(width: 20),
                _RatioStrip(
                  label: t.bg_background_volume,
                  value: draftBg.value,
                  accent: Theme.of(context).colorScheme.tertiary,
                  onChanged: onBgChanged,
                  onChangeEnd: (_) {
                    if (!explicitSave) commitDraft();
                  },
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(t.bg_ratio_use_saved),
                subtitle:
                    ratioEnabled ? null : Text(t.bg_ratio_use_saved_off_hint),
                value: ratioEnabled,
                onChanged: (v) => unawaited(bg.setVolumeRatioEnabled(v)),
              ),
              if (explicitSave)
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: commitDraft,
                    child: Text(t.save),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RatioStrip extends StatelessWidget {
  const _RatioStrip({
    required this.label,
    required this.value,
    required this.accent,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String label;
  final int value;
  final Color accent;
  final ValueChanged<int> onChanged;
  final ValueChanged<int> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Expanded(
            child: VerticalValueStrip(
              value: value,
              min: 0,
              max: 100,
              accent: accent,
              valueLabel: '$value%',
              semanticLabel: label,
              onChangeEnd: onChangeEnd,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
