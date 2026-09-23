/// mpv demuxer cache sizing preset for the media_kit (mpv) backend.
///
/// media_kit overrides mpv's own defaults and pins BOTH the forward and the
/// backward demuxer cache to `PlayerConfiguration.bufferSize` (32MiB by
/// default), which is well below mpv's upstream 150MiB/75MiB. A shallow
/// backward cache forces a re-demux on every rewind of high-bitrate media,
/// which reads as laggy fast-rewind.
///
/// These presets restore generous, device-tunable bounds. The backward cache
/// is always kept <= the forward one — mpv rejects/looks past a larger value.
enum VideoCachePreset {
  low,
  balanced,
  high;

  /// `demuxer-max-bytes` — forward demuxer cache ceiling, in bytes.
  int get maxBytes => switch (this) {
        VideoCachePreset.low => 64 * 1024 * 1024,
        VideoCachePreset.balanced => 150 * 1024 * 1024,
        VideoCachePreset.high => 300 * 1024 * 1024,
      };

  /// `demuxer-max-back-bytes` — backward (rewind) demuxer cache ceiling.
  int get backBytes => switch (this) {
        VideoCachePreset.low => 32 * 1024 * 1024,
        VideoCachePreset.balanced => 64 * 1024 * 1024,
        VideoCachePreset.high => 150 * 1024 * 1024,
      };
}
