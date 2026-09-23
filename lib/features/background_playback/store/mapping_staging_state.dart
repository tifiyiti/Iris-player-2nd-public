import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:iris/features/background_playback/model/domain/background_mapping.dart';

part 'mapping_staging_state.freezed.dart';

/// One foreground file's in-progress timeline edit.
///
/// Session-only (never persisted): the manager edits the draft, the runtime
/// keeps reading the committed DB, and an explicit Apply writes the draft.
/// [baselineUpdatedAt] is the committed row's `updatedAt` captured when the
/// edit began, used to detect that the row changed underneath the draft.
@freezed
abstract class StagedMappingTimeline with _$StagedMappingTimeline {
  const factory StagedMappingTimeline({
    required BackgroundMappingTimeline timeline,
    DateTime? baselineUpdatedAt,
    @Default(false) bool dirty,
  }) = _StagedMappingTimeline;
}

/// Session staging buffer for the mapping manager, keyed by fg identity
/// (`storageId:path`).
///
/// [staged] holds the manager's explicit drafts (Apply writes them). [apbOverlay]
/// holds the A-B editor's SESSION overlay: a commit-less exit would otherwise
/// leave the in-memory runtime on the OLD timeline, so the editor stages its
/// resolved segments here and [MappingScope] prefers them while the session
/// lives. The two live in separate maps so an APB overlay can never masquerade
/// as a dirty manager draft (or be applied by the manager's Apply).
@freezed
abstract class MappingStagingState with _$MappingStagingState {
  const factory MappingStagingState({
    @Default(<String, StagedMappingTimeline>{})
    Map<String, StagedMappingTimeline> staged,
    @Default(<String, StagedMappingTimeline>{})
    Map<String, StagedMappingTimeline> apbOverlay,
  }) = _MappingStagingState;
}
