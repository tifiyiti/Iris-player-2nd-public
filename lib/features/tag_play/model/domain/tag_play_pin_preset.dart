import 'package:freezed_annotation/freezed_annotation.dart';

part 'tag_play_pin_preset.freezed.dart';

/// A named snapshot of the global tag pin order ("pin 套装").
@freezed
abstract class TagPlayPinPreset with _$TagPlayPinPreset {
  const factory TagPlayPinPreset({
    required int id,
    required String name,

    /// Tag ids in pin order.
    @Default(<int>[]) List<int> pinnedTagIds,
    DateTime? createdAt,
  }) = _TagPlayPinPreset;
}
