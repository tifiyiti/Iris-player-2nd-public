import 'package:collection/collection.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/models/storages/volume_identity.dart';

/// A persisted local storage that must move to a new base path because its
/// volume reappeared under a different drive letter / mount point.
///
/// The entry keeps its original [id] (and therefore its data scope), so its
/// media-node tree is reused rather than re-scanned; only the base path prefix
/// of the stored paths changes.
class StorageVolumeMove {
  const StorageVolumeMove({
    required this.existing,
    required this.updated,
    required this.oldBase,
    required this.newBase,
  });

  /// The current persisted entry.
  final LocalStorage existing;

  /// The same entry with the new [LocalStorage.basePath] / name / volume id.
  final LocalStorage updated;

  /// Old base path (canonical, e.g. `D:`).
  final String oldBase;

  /// New base path (canonical, e.g. `E:`).
  final String newBase;
}

/// Planned reconciliation of the enumerated local disks against the persisted
/// entries: which entries to add and which to move.
class StorageVolumePlan {
  const StorageVolumePlan({required this.adds, required this.moves});

  final List<LocalStorage> adds;
  final List<StorageVolumeMove> moves;

  bool get isEmpty => adds.isEmpty && moves.isEmpty;
}

/// Matches enumerated local disks to persisted entries by stable volume
/// identity instead of the volatile drive letter.
///
/// Without this, a disk that moved from `D:` to `E:` is seen as brand new (its
/// generated id embeds the letter), so a full rescan rewrites every media node
/// and orphans the old ones. Matching on [LocalStorage.volumeId] lets the
/// existing entry — and its whole scanned tree — be reused.
///
/// [resolveVolumeId] resolves a stable id for a base path; it defaults to
/// [VolumeIdentity.of] and is injectable for tests. Persisted entries created
/// before v37 have no volume id and are backfilled here from their (still
/// mounted) base path, then matched like any other.
Future<StorageVolumePlan> planStorageVolumeReconcile({
  required List<LocalStorage> scanned,
  required List<LocalStorage> existing,
  Future<String?> Function(String rootPath)? resolveVolumeId,
}) async {
  final resolve = resolveVolumeId ?? VolumeIdentity.of;

  // Effective volume id per existing entry, backfilling legacy (null) ids from
  // the currently mounted base path when possible.
  final existingVolume = <String, String?>{};
  for (final e in existing) {
    var vid = e.volumeId;
    if ((vid == null || vid.isEmpty) && e.basePath.length == 1) {
      try {
        vid = await resolve(e.basePath.first);
      } catch (_) {
        vid = null;
      }
    }
    existingVolume[e.id] = (vid == null || vid.isEmpty) ? null : vid;
  }

  final adds = <LocalStorage>[];
  final moves = <StorageVolumeMove>[];
  final matchedExistingIds = <String>{};

  for (final s in scanned) {
    final scannedVolume = s.volumeId;

    // 1) Primary: stable volume identity.
    LocalStorage? match;
    if (scannedVolume != null && scannedVolume.isNotEmpty) {
      match = existing.firstWhereOrNull((e) =>
          existingVolume[e.id] == scannedVolume &&
          !matchedExistingIds.contains(e.id));
    }

    // 2) Fallback: legacy id match (both sides path-derived, no volume id).
    match ??= existing.firstWhereOrNull((e) =>
        e.id == s.id && !matchedExistingIds.contains(e.id));

    if (match == null) {
      adds.add(s);
      continue;
    }

    matchedExistingIds.add(match.id);

    final oldBase = match.basePath.join('/');
    final newBase = s.basePath.join('/');
    final newVolumeId =
        (scannedVolume != null && scannedVolume.isNotEmpty)
            ? scannedVolume
            : existingVolume[match.id];
    final baseChanged = oldBase != newBase;
    final volumeChanged = newVolumeId != match.volumeId;

    if (baseChanged || volumeChanged) {
      moves.add(StorageVolumeMove(
        existing: match,
        updated: match.copyWith(
          basePath: s.basePath,
          name: s.name,
          volumeId: newVolumeId,
        ),
        oldBase: oldBase,
        newBase: newBase,
      ));
    }
  }

  // Persist a freshly-resolved volume id even when the disk was not in the
  // scanned set (e.g. an enumeration edge): same base path, new identity, so
  // the NEXT letter change can match it.
  for (final e in existing) {
    if (matchedExistingIds.contains(e.id)) continue;
    final resolved = existingVolume[e.id];
    if (resolved == null || resolved == e.volumeId) continue;
    moves.add(StorageVolumeMove(
      existing: e,
      updated: e.copyWith(volumeId: resolved),
      oldBase: e.basePath.join('/'),
      newBase: e.basePath.join('/'),
    ));
  }

  return StorageVolumePlan(adds: adds, moves: moves);
}
