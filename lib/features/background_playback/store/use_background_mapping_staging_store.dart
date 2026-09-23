import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/background_playback/model/domain/background_mapping.dart';
import 'package:iris/features/background_playback/store/mapping_staging_state.dart';

/// Session-only staging buffer of the mapping manager.
///
/// Edits made in the manager live here instead of the database, so applying a
/// draft cannot disturb what 副音 is currently playing (the runtime keeps
/// reading the committed timeline). A per-fg Apply writes the staged timeline
/// and clears its draft.
class BackgroundMappingStagingStore extends Store<MappingStagingState> {
  BackgroundMappingStagingStore() : super(const MappingStagingState());

  StagedMappingTimeline? stagedFor(String fgKey) => state.staged[fgKey];

  bool isDirty(String fgKey) => state.staged[fgKey]?.dirty ?? false;

  /// Keys with a dirty draft (Level-1 badge).
  Set<String> get dirtyKeys => {
        for (final e in state.staged.entries)
          if (e.value.dirty) e.key,
      };

  bool get hasStaged => state.staged.isNotEmpty;

  /// Stages [timeline] as a dirty draft for its fg. [baselineUpdatedAt] records
  /// the committed row's `updatedAt` so Apply can detect an external change;
  /// when omitted the existing baseline (if any) is preserved.
  void stage(
    BackgroundMappingTimeline timeline, {
    DateTime? baselineUpdatedAt,
  }) {
    final key = stagingKey(timeline.storageId, timeline.path);
    final next = Map<String, StagedMappingTimeline>.of(state.staged);
    next[key] = StagedMappingTimeline(
      timeline: timeline,
      baselineUpdatedAt:
          baselineUpdatedAt ?? state.staged[key]?.baselineUpdatedAt,
      dirty: true,
    );
    set(state.copyWith(staged: next));
  }

  void discard(String fgKey) {
    if (!state.staged.containsKey(fgKey)) return;
    final next = Map<String, StagedMappingTimeline>.of(state.staged)
      ..remove(fgKey);
    set(state.copyWith(staged: next));
  }

  void discardAll() {
    if (state.staged.isEmpty) return;
    set(state.copyWith(staged: const <String, StagedMappingTimeline>{}));
  }

  // ── A-B editor session overlay ──
  //
  // Kept in its OWN map (never `staged`) so a commit-less editor exit can make
  // the alignment live in memory without becoming a dirty manager draft. The
  // overlay is session-scoped: it is dropped when the APB session ends or the
  // foreground stops/switches files (see the callers in the editor + mapping
  // scope).

  StagedMappingTimeline? apbOverlayFor(String fgKey) => state.apbOverlay[fgKey];

  bool hasApbOverlay(String fgKey) => state.apbOverlay.containsKey(fgKey);

  /// Stages [timeline] as the live in-memory alignment for its fg, overriding
  /// the committed DB timeline until the session ends.
  void stageApbOverlay(BackgroundMappingTimeline timeline) {
    final key = stagingKey(timeline.storageId, timeline.path);
    final next = Map<String, StagedMappingTimeline>.of(state.apbOverlay);
    next[key] = StagedMappingTimeline(timeline: timeline, dirty: false);
    set(state.copyWith(apbOverlay: next));
  }

  void discardApbOverlay(String fgKey) {
    if (!state.apbOverlay.containsKey(fgKey)) return;
    final next = Map<String, StagedMappingTimeline>.of(state.apbOverlay)
      ..remove(fgKey);
    set(state.copyWith(apbOverlay: next));
  }

  void discardAllApbOverlays() {
    if (state.apbOverlay.isEmpty) return;
    set(state.copyWith(apbOverlay: const <String, StagedMappingTimeline>{}));
  }

  static String stagingKey(String storageId, String path) =>
      '$storageId:$path';
}

BackgroundMappingStagingStore useBackgroundMappingStagingStore() =>
    create(() => BackgroundMappingStagingStore());
