import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/models/file.dart';

part 'play_queue_source.freezed.dart';
part 'play_queue_source.g.dart';

@freezed
abstract class PlayQueueSource with _$PlayQueueSource {
  const factory PlayQueueSource.explicit({
    required List<PlayQueueItem> items,
  }) = ExplicitSource;

  const factory PlayQueueSource.allMedia({
    MediaType? mediaType,
    String? storageId,
  }) = AllMediaSource;

  const factory PlayQueueSource.folder({
    required String storageId,
    required String parentPath,
    MediaType? mediaType,
    @Default(true) bool recursive,
  }) = FolderSource;

  factory PlayQueueSource.fromJson(Map<String, dynamic> json) =>
      _$PlayQueueSourceFromJson(json);
}
