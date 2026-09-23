import 'package:flutter/material.dart';
import 'package:iris/models/player.dart';
import 'package:iris/utils/get_localizations.dart';

/// Subtitle/audio sync nudge bar inside the track panel.
///
/// Rendered only when the backend reports [MediaPlayer.supportsSyncAdjustment]
/// (mediaKit). Shares the exact 0.5s ladder with the keyboard triads
/// (`>` `<` `/` and Shift variants) via [kSyncStep].
class SyncAdjustBar extends StatelessWidget {
  const SyncAdjustBar({super.key, required this.player});

  final MediaPlayer player;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Row(
        children: [
          _cluster(context, Icons.subtitles_rounded, t.track_subtitle,
              () => player.nudgeSubtitleSync(-1),
              () => player.resetSubtitleSync(),
              () => player.nudgeSubtitleSync(1)),
          const SizedBox(width: 16),
          _cluster(context, Icons.graphic_eq_rounded, t.track_audio,
              () => player.nudgeAudioSync(-1),
              () => player.resetAudioSync(),
              () => player.nudgeAudioSync(1)),
          const Spacer(),
          Text(
            '±${kSyncStep.inMilliseconds / 1000}s',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _cluster(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onBack,
    VoidCallback onReset,
    VoidCallback onForward,
  ) {
    final t = getLocalizations(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: '-0.5s',
          icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
          onPressed: onBack,
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: t.track_sync_reset,
          icon: const Icon(Icons.restart_alt_rounded, size: 18),
          onPressed: onReset,
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: '+0.5s',
          icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
          onPressed: onForward,
        ),
      ],
    );
  }
}
