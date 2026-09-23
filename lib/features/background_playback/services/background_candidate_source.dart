import 'package:iris/models/file.dart';

/// A candidate provider of the 副音 queue: resolves concrete single media
/// files. This is the extension seam for future source kinds (folder source,
/// path+tag source, … per the 需求 §五) — the background playback core only
/// ever consumes [FileItem]s from here.
abstract interface class BackgroundCandidateSource {
  String get id;

  /// Existing, playable single files. Missing media must be silently absent,
  /// never thrown. Sources cap their own output at [cap].
  Future<List<FileItem>> resolveCandidates({int cap = 400});
}

/// Registry of candidate sources; the launch/refresh actions try them in
/// registration order and use the first non-empty result.
abstract final class BackgroundCandidateSources {
  static final List<BackgroundCandidateSource> _sources = [];

  static void register(BackgroundCandidateSource source) {
    _sources.add(source);
  }

  static List<BackgroundCandidateSource> get all => List.unmodifiable(_sources);

  /// First source yielding candidates (ordered), else null.
  static Future<List<FileItem>?> firstNonEmpty({int cap = 400}) async {
    for (final source in List.of(_sources)) {
      final candidates = await source.resolveCandidates(cap: cap);
      if (candidates.isNotEmpty) return candidates;
    }
    return null;
  }
}
