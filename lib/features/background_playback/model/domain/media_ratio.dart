import 'package:freezed_annotation/freezed_annotation.dart';

part 'media_ratio.freezed.dart';
part 'media_ratio.g.dart';

/// One foreground/background volume-ratio pair (percent of the master volume).
///
/// Values live per foreground media (an override) or as the global default;
/// the background playback store resolves which one applies for the file that
/// is currently playing.
@freezed
abstract class MediaRatio with _$MediaRatio {
  const factory MediaRatio({
    @Default(30) int fgPercent,
    @Default(100) int bgPercent,
  }) = _MediaRatio;

  factory MediaRatio.fromJson(Map<String, dynamic> json) =>
      _$MediaRatioFromJson(json);
}
