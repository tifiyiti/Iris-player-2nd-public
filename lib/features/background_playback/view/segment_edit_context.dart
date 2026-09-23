import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/background_playback/engine/background_playback_engine.dart';
import 'package:iris/features/background_playback/model/domain/background_mapping.dart';
import 'package:iris/features/background_playback/model/domain/segment_edit_draft.dart';
import 'package:iris/features/background_playback/resolver/active_mapping_resolver.dart';
import 'package:iris/features/background_playback/services/current_bg_resolver.dart';
import 'package:iris/features/virtual_media/interaction/controller/foreground_window_resolver.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/utils/path_conv.dart';
import 'package:provider/provider.dart';

/// Everything an A-B editor surface needs about the CURRENT editing session.
class SegmentEditContext {
  const SegmentEditContext({
    required this.active,
    required this.fgFile,
    required this.fgStorageId,
    required this.fgPath,
    required this.fgWindow,
    required this.bgFile,
    required this.bgDurMs,
    required this.draft,
    required this.existing,
    required this.allSegments,
    required this.resolvedSlices,
    this.baselineUpdatedAt,
  });

  final bool active;
  final FileItem? fgFile;
  final String fgStorageId;
  final String fgPath;

  /// The PHYSICAL foreground window under edit (VM undone) — the editor must
  /// never use the merged virtual duration here.
  final ForegroundWindow fgWindow;

  /// The 副音 file audibly loaded right now (mapped › engine › natural), or
  /// null when 副音 truly has nothing loaded.
  final FileItem? bgFile;

  /// Physical foreground duration (`fgWindow.durationMs`).
  int get fgDurMs => fgWindow.durationMs;

  /// NOTE: there is deliberately no `fgPosMs` here. A per-tick POSITION in this
  /// context would rebuild the whole editor (panel + dial + button bar) on every
  /// playback tick — the surfaces that paint a position subscribe in their own
  /// leaf, and handlers read it at event time via `fgPhysicalPositionNow`.

  final int bgDurMs;
  final SegmentEditDraft? draft;

  /// Persisted segments of the foreground file, EXCLUDING the row currently
  /// being edited (so the overlay never draws the draft twice). This is the
  /// list the overlap policies work against.
  final List<MappingSegment> existing;

  /// The complete persisted timeline, including the row under edit — used for
  /// the management list so an edited row does not vanish from it.
  final List<MappingSegment> allSegments;

  /// The RESOLVED foreground axis for display: each activation-order winner
  /// clipped to its slice, excluding the row under edit (which the editor draws
  /// as the active span). This is what makes the editor's fg axis agree with
  /// playback and the manager overview — a shadowed segment never shows its
  /// full value.
  final List<MappingSegment> resolvedSlices;

  /// The committed row's `updatedAt` when the editor loaded it — the optimistic
  /// baseline a stage-only Save records so the manager's Apply can detect an
  /// external change.
  final DateTime? baselineUpdatedAt;
}

/// Loads the live A-B editing context. Only call from a surface that renders
/// while [BackgroundPlaybackState.segmentEditMode] is on (the engine provider
/// must exist).
SegmentEditContext useSegmentEditContext(BuildContext context) {
  final bg = useBackgroundPlaybackStore();
  final active = bg.select(context, (s) => s.segmentEditMode);
  final draft = bg.select(context, (s) => s.segmentEditDraft);

  final playQueue = usePlayQueueStore().select(context, (s) => s.playQueue);
  final playIndex = usePlayQueueStore().select(context, (s) => s.currentIndex);
  final FileItem? fgFile = useMemoized(
    () {
      if (playQueue.isEmpty || playIndex < 0) return null;
      final i = playQueue.indexWhere((e) => e.index == playIndex);
      if (i < 0 || i >= playQueue.length) return null;
      return playQueue[i].file;
    },
    [playQueue, playIndex],
  );
  final String fgStorageId = fgFile?.storageId ?? '';
  final String fgPath =
      fgFile == null ? '' : canonicalDbPath(fgFile.path.join('/'));

  // Physical foreground window (VM merged timeline undone) + the live bg file.
  // DURATION only: the position is read by the leaf surfaces that paint it, so
  // this context never rebuilds on a playback tick.
  final fgWindow = useForegroundDuration(context);
  final FileItem? bgFile = useCurrentBgFile(context);

  // Duration ONLY — selecting the whole engine would recompute this context on
  // every position tick.
  final int bgDurMs = context
      .select<BackgroundPlaybackEngine, int>((e) => e.duration.inMilliseconds);

  final timeline = useState<BackgroundMappingTimeline?>(null);
  final editingId = draft?.editingId ?? 0;
  useEffect(() {
    if (!active || fgFile == null) {
      timeline.value = null;
      return null;
    }
    var stale = false;
    DbModule.bgMappingRepo
        .getTimelineForFg(storageId: fgStorageId, path: fgPath)
        .then((t) {
      if (!stale) timeline.value = t;
    });
    return () {
      stale = true;
    };
  }, [active, fgStorageId, fgPath]);

  final allSegments = timeline.value?.sortedSegments ?? const <MappingSegment>[];
  final existing = useMemoized(
    () {
      if (editingId == 0) return allSegments;
      return [
        for (final s in allSegments)
          if (s.id != editingId) s,
      ];
    },
    [timeline.value, editingId],
  );

  // Resolved fg axis (winners only, clipped to their slice) for display.
  final int fgDurMs = fgWindow.durationMs;
  final resolvedSlices = useMemoized(
    () {
      if (fgDurMs <= 0 || allSegments.isEmpty) {
        return const <MappingSegment>[];
      }
      final blocks = ActiveMappingResolver.visibleBlocks(
        segments: allSegments,
        fgTotalMs: fgDurMs,
      );
      final out = <MappingSegment>[];
      for (final b in blocks) {
        final seg = b.segment;
        if (seg == null) continue;
        if (seg.id != 0 && seg.id == editingId) continue;
        out.add(seg.copyWith(fgStartMs: b.startMs, fgEndMs: b.endMs));
      }
      return out;
    },
    [allSegments, fgDurMs, editingId],
  );

  return SegmentEditContext(
    active: active,
    fgFile: fgFile,
    fgStorageId: fgStorageId,
    fgPath: fgPath,
    fgWindow: fgWindow,
    bgFile: bgFile,
    bgDurMs: bgDurMs,
    draft: draft,
    existing: existing,
    allSegments: allSegments,
    resolvedSlices: resolvedSlices,
    baselineUpdatedAt: timeline.value?.updatedAt,
  );
}

/// Kept so callers can read the ambient foreground player without importing
/// provider directly (used by the editor's transport buttons).
MediaPlayer readForegroundPlayer(BuildContext context) =>
    context.read<MediaPlayer>();
