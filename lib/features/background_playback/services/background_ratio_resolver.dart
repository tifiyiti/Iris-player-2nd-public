import 'package:iris/features/background_playback/model/domain/media_ratio.dart';

/// Resolves which fg/bg volume-ratio pair applies right now (sub_media §5.5).
///
/// Three layers, most specific first: the ACTIVE mapping segment's saved pair
/// (`segmentOverride`, v27), a per-foreground-media override, then the global
/// default. An empty override falls through. When the user cleared "use saved
/// ratio" the whole ratio is bypassed and both sides run at the master volume
/// (100/100 — i.e. no attenuation).
MediaRatio resolveEffectiveRatio({
  required bool volumeRatioEnabled,
  required MediaRatio global,
  required Map<String, MediaRatio> perMedia,
  required String? fgKey,
  MediaRatio? segmentOverride,
}) {
  if (!volumeRatioEnabled) {
    return const MediaRatio(fgPercent: 100, bgPercent: 100);
  }
  if (segmentOverride != null) return _clamped(segmentOverride);
  final key = fgKey;
  final override = key == null ? null : perMedia[key];
  return _clamped(override ?? global);
}

MediaRatio _clamped(MediaRatio r) => r.copyWith(
      fgPercent: r.fgPercent.clamp(0, 100),
      bgPercent: r.bgPercent.clamp(0, 100),
    );
