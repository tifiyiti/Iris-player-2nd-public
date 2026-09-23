import 'package:freezed_annotation/freezed_annotation.dart';

part 'media_library.freezed.dart';
part 'media_library.g.dart';

@freezed
abstract class MediaLibrary with _$MediaLibrary {
  const factory MediaLibrary({
    required String id,
    required String name,
    required MediaLibraryType type,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _MediaLibrary;

  factory MediaLibrary.fromJson(Map<String, dynamic> json) => _$MediaLibraryFromJson(json);
}

enum MediaLibraryType {
  system, // default
  user,
}
