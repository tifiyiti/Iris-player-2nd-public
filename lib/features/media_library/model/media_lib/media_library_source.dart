import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:iris/features/media_library/model/enum/media_lib_sources.dart';

part 'media_library_source.freezed.dart';
part 'media_library_source.g.dart';

@freezed
abstract class MediaLibrarySource with _$MediaLibrarySource {
  const factory MediaLibrarySource({
    required int id,
    required String libraryId,
    required String storageId,
    List<String>? path, // null = full storage
    String? name, // optional display name, falls back to path.last
    @Default(0) int pathDepth,
    MediaSourceKind? kind,
    // Aggregates
    @Default(0) int totalMediaCount,
    @Default(0) int totalDirCount,
    @Default(0) int totalItemCount,
    @Default(0) int totalSizeInBytes,
    @Default(0) int totalDurationMs,
    //
    DateTime? modifiedAt,
    DateTime? createdAt,
  }) = _MediaLibrarySource;

  factory MediaLibrarySource.fromJson(Map<String, dynamic> json) =>
      _$MediaLibrarySourceFromJson(json);
}
