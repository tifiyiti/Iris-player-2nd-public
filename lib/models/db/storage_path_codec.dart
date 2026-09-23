import 'package:iris/utils/path_conv.dart';

/// Converts between the DOMAIN path form and the DB-stored path form for
/// `media_nodes`.
///
/// - DOMAIN: absolute, storage-base-inclusive, canonical (`D:/Movies/a.mp4`,
///   `storage/emulated/0/Movies/a.mp4`, `<treeUri>/Movies/a.mp4`).
/// - DB: relative to the storage's base path (`Movies/a.mp4`, `''` = root).
///
/// The DB form is the stable identity: a drive-letter reassignment changes only
/// the storage's `base_path`, never the stored rows, so a re-mounted disk needs
/// ZERO media-node writes. The base is resolved from the owning entry's id via
/// [baseResolver] (wired at startup from the storage store).
///
/// Both directions are IDEMPOTENT: a path already in the target form passes
/// through unchanged. That makes it safe to call on either form at every
/// boundary, so a missed conversion can never corrupt a path by stripping or
/// prepending twice.
abstract final class StoragePathCodec {
  /// Resolves a storage id to its absolute base segments (e.g. `['D:']`), or
  /// null when the storage is unknown / has no meaningful base (remote root
  /// `/`, empty) — in which case no conversion happens.
  static List<String>? Function(String storageId) baseResolver = (_) => null;

  static List<String>? _baseSegments(String storageId) {
    final base = baseResolver(storageId);
    if (base == null || base.isEmpty) return null;
    final canonical = canonicalDbPath(base.join('/'));
    if (canonical.isEmpty) return null;
    // Android SAF tree URIs are stable and path-embedded on purpose; leaving
    // them absolute keeps the SAF resolution/backfill logic unchanged.
    if (isSafPath(canonical)) return null;
    final segments = pathConv(canonical);
    return segments.isEmpty ? null : segments;
  }

  /// DOMAIN (absolute) → DB (relative) canonical string.
  static String relativize(String storageId, String domainCanonical) {
    final base = _baseSegments(storageId);
    if (base == null) return domainCanonical;
    final segments = pathConv(domainCanonical);
    if (segments.length < base.length) return domainCanonical;
    for (var i = 0; i < base.length; i++) {
      if (segments[i] != base[i]) return domainCanonical;
    }
    return segments.sublist(base.length).join('/');
  }

  /// DB (relative) → DOMAIN (absolute) canonical string.
  static String absolutize(String storageId, String storedCanonical) {
    final base = _baseSegments(storageId);
    if (base == null) return storedCanonical;
    final segments = pathConv(storedCanonical);
    if (segments.length >= base.length) {
      var alreadyAbsolute = true;
      for (var i = 0; i < base.length; i++) {
        if (segments[i] != base[i]) {
          alreadyAbsolute = false;
          break;
        }
      }
      if (alreadyAbsolute) return storedCanonical;
    }
    return [...base, ...segments].join('/');
  }
}
