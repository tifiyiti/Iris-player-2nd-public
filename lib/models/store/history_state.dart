import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:flutter/foundation.dart';
import 'package:iris/models/progress.dart';

part 'history_state.freezed.dart';
part 'history_state.g.dart';

@freezed
abstract class HistoryState with _$HistoryState {
  const factory HistoryState({
    @Default({}) Map<String, Progress> history,

    /// Maximum number of history records kept (FIFO eviction of the oldest).
    /// Persisted so a future user setting can tune it; defaults to 500.
    @Default(500) int maxHistoryRecords,
  }) = _HistoryState;

  factory HistoryState.fromJson(Map<String, dynamic> json) =>
      _$HistoryStateFromJson(json);
}
