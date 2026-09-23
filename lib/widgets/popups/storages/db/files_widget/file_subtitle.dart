import 'package:flutter/material.dart' hide Chip;
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/media_library/store/use_playback_progress_store.dart';
import 'package:iris/features/media_library/view/widgets/progress_chip.dart';
import 'package:iris/models/file.dart';
import 'package:iris/utils/file_size_convert.dart';
import 'package:iris/utils/path_conv.dart';
import 'package:iris/widgets/chip.dart' show Chip;

class FileSubtitle extends HookWidget {
  const FileSubtitle({
    super.key,
    required this.file,
    this.durablePositionMs,
    this.durableDurationMs,
  });

  final FileItem file;

  /// Durable playback progress from the media library (media_nodes columns),
  /// used as the fallback when HistoryStore has no entry (e.g. after clearing
  /// history), so progress stays visible.
  final int? durablePositionMs;
  final int? durableDurationMs;

  @override
  Widget build(BuildContext context) {
    // Live progress comes from the in-memory PlaybackProgressStore (updated
    // every second while playing); when it is absent, fall back to the durable
    // media-library values. Keyed canonically (not file.getID()) so scenario-
    // and storage-surface entries resolve the same file.
    final live = usePlaybackProgressStore().select(
      context,
      // (state) => state[file.getID()],  // legacy: surface-dependent uri key
      (state) => state[canonicalProgressKey(file.storageId, file.path,
          uri: file.uri)], // unified
    );
    final positionMs = live?.$1 ?? durablePositionMs;
    final durationMs = live?.$2 ?? durableDurationMs;

    final List<Widget> children = [];

    // File size
    if (file.size != 0) {
      children.add(Text(
        "${fileSizeConvert(file.size)} MB",
        style: const TextStyle(fontSize: 13),
      ));
      children.add(const SizedBox(width: 8)); // <-- matches original
    }

    // Last modified
    if (file.lastModified != null) {
      children.add(Expanded(
        child: Text(
          file.lastModified.toString().split('.')[0],
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
          ),
        ),
      ));
      children.add(const SizedBox(width: 8)); // <-- matches original
    }

    // Progress chip: video only, when there is a live or durable record.
    if (file.type == ContentType.video &&
        durationMs != null &&
        (live != null || durablePositionMs != null)) {
      children.add(ProgressChip(
        positionMs: positionMs ?? 0,
        durationMs: durationMs,
      ));
      children.add(const SizedBox(width: 8)); // <-- add spacing after progress chip
    }

    // Subtitle chips
    children.addAll(_buildSubtitleChips());

    return Row(
      mainAxisSize: MainAxisSize.min,
      textBaseline: TextBaseline.ideographic,
      children: children,
    );
  }

  List<Widget> _buildSubtitleChips() {
    final types = file.subtitles.map((s) => s.uri.split('.').last.toUpperCase()).toSet().toList();

    return types.map((type) {
      return Padding(
        padding: const EdgeInsets.only(left: 4), // small left gap between chips
        child: Chip(
          text: type,
          primary: true,
        ),
      );
    }).toList();
  }
}
