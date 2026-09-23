import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';

part 'media_node_page_result.freezed.dart';
part 'media_node_page_result.g.dart';

@freezed
abstract class MediaNodePageResult with _$MediaNodePageResult {
  const MediaNodePageResult._();

  const factory MediaNodePageResult({
    required List<MediaNode> items,
    required int totalItems,
    required int totalPages,
    required int currentPage,
    required int pageSize,
  }) = _MediaNodePageResult;

  factory MediaNodePageResult.fromJson(Map<String, dynamic> json) =>
      _$MediaNodePageResultFromJson(json);

  bool get hasNextPage => currentPage < totalPages;
  bool get hasPreviousPage => currentPage > 1;
}
