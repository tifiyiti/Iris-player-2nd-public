import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';

/// Phone-PORTRAIT bottom-bar alignment editor.
///
/// One dialog, two independent rows — the normal playback group and the group-2
/// 副音 quick bar — each a 3-way left/center/right [SegmentedButton]. Selection
/// commits LIVE (the settings page's subtitle and the bar update behind the
/// dialog); there is no text input, so a plain [AlertDialog] is correct here.
///
/// PORTRAIT-only: the side panel and the standalone desktop 副音 row are not
/// touched. See [PortraitBarAlign].
Future<void> showPortraitBarAlignDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const PortraitBarAlignDialog(),
  );
}

class PortraitBarAlignDialog extends HookWidget {
  const PortraitBarAlignDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final AppStore store = useAppStore();
    // Field-scoped subscriptions: only the two values this dialog edits.
    final PortraitBarAlign playback =
        store.select(context, (s) => s.portraitPlaybackAlign);
    final PortraitBarAlign subAudio =
        store.select(context, (s) => s.portraitSubAudioAlign);

    return AlertDialog(
      title: Text(t.set_portrait_bar_align),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AlignRow(
            label: t.set_portrait_bar_align_playback,
            value: playback,
            onChanged: (v) => unawaited(store.updatePortraitPlaybackAlign(v)),
          ),
          const SizedBox(height: 16),
          _AlignRow(
            label: t.set_portrait_bar_align_sub_audio,
            value: subAudio,
            onChanged: (v) => unawaited(store.updatePortraitSubAudioAlign(v)),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.close),
        ),
      ],
    );
  }
}

/// One labelled 3-way alignment row.
class _AlignRow extends StatelessWidget {
  const _AlignRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final PortraitBarAlign value;
  final ValueChanged<PortraitBarAlign> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        // Expands to the dialog width; `showSelectedIcon: false` keeps each
        // segment compact enough for a narrow phone, and the short 左/中/右
        // labels never wrap.
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<PortraitBarAlign>(
            segments: [
              ButtonSegment<PortraitBarAlign>(
                value: PortraitBarAlign.left,
                icon: const Icon(Icons.align_horizontal_left_rounded),
                label: Text(t.ed_pos_left),
              ),
              ButtonSegment<PortraitBarAlign>(
                value: PortraitBarAlign.center,
                icon: const Icon(Icons.align_horizontal_center_rounded),
                label: Text(t.ed_pos_center),
              ),
              ButtonSegment<PortraitBarAlign>(
                value: PortraitBarAlign.right,
                icon: const Icon(Icons.align_horizontal_right_rounded),
                label: Text(t.ed_pos_right),
              ),
            ],
            selected: {value},
            showSelectedIcon: false,
            onSelectionChanged: (Set<PortraitBarAlign> sel) =>
                onChanged(sel.first),
          ),
        ),
      ],
    );
  }
}
