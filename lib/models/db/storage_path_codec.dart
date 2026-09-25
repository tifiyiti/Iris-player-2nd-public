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

  /// True when [storedCanonical] names a directory ABOVE the storage base
  /// (a strict ancestor prefix of it), e.g. stored `F:/dl` with base
  /// `F:/dl/ar`.
  ///
  /// Such rows are phantoms: pre-fix scans built directory nodes from
  /// absolute segments, so the base itself and everything above it leaked
  /// into the DB. The topmost phantom carries a NULL parent, which every
  /// root-level read mistakes for a real root child.
  static bool isAboveBase(String storageId, String storedCanonical) {
    final base = _baseSegments(storageId);
    if (base == null || storedCanonical.isEmpty) return false;
    final b = base.join('/');
    return b != storedCanonical && b.startsWith('$storedCanonical/');
  }

  /// True when [storedCanonical] is the storage base itself in ABSOLUTE form
  /// (e.g. stored `F:` with base `F:`, or stored `F:/dl/ar` with base
  /// `F:/dl/ar`).
  ///
  /// Pre-fix scans built the storage-root self node from absolute segments,
  /// so old databases may carry the root twice: this absolute row plus (after
  /// a fixed scan) the relative `''` row. The absolute row is a phantom: it
  /// can never be addressed through [relativize] (which maps it to `''`), and
  /// with a NULL parent on a drive-root base it counts as an unscanned root
  /// child forever, permanently blocking the root `scanDone` stamp.
  /// [isAboveBase] does NOT match it (it is the base itself, not strictly
  /// above it), hence the separate predicate. Remove it by EXACT stored-path
  /// match only — never by prefix: its relativized form is `''`, and a prefix
  /// delete on `''` would wipe the real root container instead.
  static bool isStaleAbsoluteBase(String storageId, String storedCanonical) {
    if (storedCanonical.isEmpty) return false;
    final base = _baseSegments(storageId);
    if (base == null) return false;
    if (storedCanonical != base.join('/')) return false;
    return relativize(storageId, storedCanonical).isEmpty;
  }
}
