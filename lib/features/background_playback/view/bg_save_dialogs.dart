import 'package:flutter/material.dart';
import 'package:iris/features/background_playback/model/domain/background_mapping.dart';
import 'package:iris/features/background_playback/resolver/active_mapping_resolver.dart';
import 'package:iris/features/background_playback/view/manager/mapping_timeline_overview.dart';
import 'package:iris/utils/get_localizations.dart';

/// Save-time decision when the editor was opened ON an in-use saved segment.
enum BgSaveConflictChoice {
  /// Replace the segment that was in use (keeps its lit position) — default.
  overwrite,

  /// Append as a new segment, taking the next activation order (wins overlap).
  asNew,
}

/// Asks whether an in-use mapping should be overwritten or saved as a new
/// segment. Returns null when dismissed (the save is aborted).
///
/// [name] identifies the mapping being replaced (the background's display name).
Future<BgSaveConflictChoice?> showBgSaveConflictDialog(
  BuildContext context, {
  required String name,
}) async {
  final t = getLocalizations(context);
  final choice = await showDialog<BgSaveConflictChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.layers_rounded),
      title: Text(t.bg_mapping_manager_save_source_title),
      content: Text(t.bg_mapping_manager_save_source_body(name)),
      actions: [
        TextButton(
          key: const ValueKey('bg_save_as_new'),
          onPressed: () =>
              Navigator.of(ctx).pop(BgSaveConflictChoice.asNew),
          child: Text(t.bg_mapping_manager_save_as_new),
        ),
        FilledButton(
          key: const ValueKey('bg_save_overwrite'),
          onPressed: () =>
              Navigator.of(ctx).pop(BgSaveConflictChoice.overwrite),
          child: Text(t.bg_mapping_manager_save_overwrite),
        ),
      ],
    ),
  );
  return choice;
}

/// Post-save confirmation that shows the RESULT of the save on the same 0–100%
/// axis the manager uses: the resolved mapping (activation-order winners only),
/// never the full value of a shadowed segment.
Future<void> showBgSaveResultDialog(
  BuildContext context, {
  required List<MappingSegment> segments,
  required int fgTotalMs,
  required String title,
  required String message,
}) async {
  final t = getLocalizations(context);
  final blocks = ActiveMappingResolver.visibleBlocks(
    segments: segments,
    fgTotalMs: fgTotalMs,
  );
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final media = MediaQuery.of(ctx);
      return AlertDialog(
        icon: Icon(Icons.check_circle_outline, color: theme.colorScheme.primary),
        title: Text(title),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 480,
            maxHeight: media.size.height * 0.5,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(message),
                const SizedBox(height: 12),
                MappingTimelineOverview(
                  blocks: blocks,
                  fgTotalMs: fgTotalMs,
                  semanticsLabel: t.bg_mapping_manager_overview_label,
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            key: const ValueKey('bg_save_result_ok'),
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(t.ok),
          ),
        ],
      );
    },
  );
}
