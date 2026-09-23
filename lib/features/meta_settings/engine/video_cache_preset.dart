import 'package:iris/models/enums/video_cache_preset.dart';
import 'package:iris/models/store/app_state.dart';

// Pure resolver for the media_kit demuxer cache sizing preset.
// Follows the same contract as `resolveResumeOnStartup`: when the metadata
// gate is OFF the row is unavailable (DefVisibility hides it), so the run
// degrades to `balanced` — the value the def declares as its default.

VideoCachePreset resolveVideoCachePreset(
  AppState state, {
  required bool metadataEnabled,
}) =>
    metadataEnabled ? state.videoCachePreset : VideoCachePreset.balanced;
