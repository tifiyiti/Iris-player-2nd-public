import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:iris/features/media_library/play_queue/models/play_queue_source.dart';

part 'query_play_queue_state.freezed.dart';
part 'query_play_queue_state.g.dart';

enum PlayQueueOrder { sequential, shuffled }

@freezed
abstract class QueryPlayQueueState with _$QueryPlayQueueState {
  const factory QueryPlayQueueState({
    @Default([]) List<PlayQueueSource> sources,
    @Default(PlayQueueOrder.sequential) PlayQueueOrder order,
    @Default(0) int currentVirtualPos,
    @Default(0) int currentOriginalPos,
    required int totalCount,
    int? shuffleSeed,
    @Default(50) int itemsPerPage,
    @Default(10000) int maxItemsPerPage,
    @Default(1000) int maxMemoryListLimit,
  }) = _QueryPlayQueueState;

  factory QueryPlayQueueState.fromJson(Map<String, dynamic> json) =>
      _$QueryPlayQueueStateFromJson(json);
}
