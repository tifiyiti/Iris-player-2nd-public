import 'dart:io';

import 'package:flutter/foundation.dart' show immutable, visibleForTesting;
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:iris/features/media_library/model/enum/basic_enum.dart'
    show SortDirection;
import 'package:iris/features/media_library/model/enum/media_lib_sources.dart'
    show MediaSourceKind;
import 'package:iris/features/media_library/model/enum/media_node.dart'
    show MediaNodeKind;
import 'package:iris/features/media_library/model/media_lib/media_node.dart'
    show MediaNode, MediaType;
import 'package:iris/features/meta_settings/engine/browse_media_scope.dart'
    show scopeMediaTypes;
import 'package:iris/features/meta_settings/engine/browse_scope_snapshot.dart'
    show currentBrowseMediaScope;
import 'package:iris/features/scenario_playback/actions/scan_play_gate.dart';
import 'package:iris/features/scenario_playback/actions/scenario_append_actions.dart';
import 'package:iris/features/scenario_playback/actions/scenario_override_actions.dart';
import 'package:iris/features/scenario_playback/actions/scenario_playback_actions.dart';
import 'package:iris/features/scenario_playback/model/enum/scenario_sort_field.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/storages/local.dart' show getLocalStorages;
import 'package:iris/models/storages/storage.dart';
import 'package:iris/models/storages/volume_identity.dart';
import 'package:iris/models/store/app_state.dart' show BrowseMediaScope;
import 'package:iris/store/use_storage_store.dart';
import 'package:iris/store/warning_dialogs.dart';
import 'package:iris/utils/check_content_type.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/path_conv.dart';
import 'package:iris/widgets/dialogs/show_confirm_suppressible_dialog.dart';
import 'package:iris/widgets/popups/storages/db/storages_utils/storage_utils.dart';

/// Kind of a single dropped filesystem target after a stat.
enum DragDropEntryKind { directory, file, ignored }

/// Which play action a drop must perform, decided by the vertical zone the
/// pointer sits in (PotPlayer-style): the top strip APPENDS to the play queue,
/// the rest OVERRIDES playback.
enum DragDropZone { append, override }

/// Default share of the player height that appends (PotPlayer uses 30%).
const double kDropAppendPercentDefault = 30;

/// Hard lower/upper bounds of the append-zone split, regardless of any
/// configured value.
const double kDropAppendPercentMin = 10;
const double kDropAppendPercentMax = 90;

/// Clamps a configured append-zone percentage into the hard bounds; a missing
/// value degrades to [kDropAppendPercentDefault].
double clampDropAppendPercent(double? value) => (value ?? kDropAppendPercentDefault)
    .clamp(kDropAppendPercentMin, kDropAppendPercentMax)
    .toDouble();

/// Pure zone decision for a drop. [localY] is relative to the top of the drop
/// target and [boxHeight] is that target's height; an unknown/zero height
/// degrades to [DragDropZone.override] (the safe "play" default).
DragDropZone resolveDropZone({
  required double localY,
  required double boxHeight,
  required double appendPercent,
}) {
  if (boxHeight <= 0 || !boxHeight.isFinite) return DragDropZone.override;
  final threshold = clampDropAppendPercent(appendPercent) / 100.0;
  final fraction = localY / boxHeight;
  if (fraction.isNaN) return DragDropZone.override;
  return fraction < threshold ? DragDropZone.append : DragDropZone.override;
}

/// Pure classifier: a dropped target is a directory, a playable file, or
/// ignored. The filesystem kind is resolved by the CALLER (stat) and decides
/// FIRST — a directory named `Movie.2020` must never be mistaken for media by
/// an extension probe.
DragDropEntryKind classifyDropKind({
  required bool exists,
  required bool isDirectory,
}) {
  if (!exists) return DragDropEntryKind.ignored;
  return isDirectory ? DragDropEntryKind.directory : DragDropEntryKind.file;
}

/// Whether [contentType] can enter the play queue.
bool isPlayableContentType(ContentType contentType) =>
    contentType == ContentType.video || contentType == ContentType.audio;

/// Folds a path segment for case/separator-insensitive matching. Windows drive
/// letters and UNC hosts are case-insensitive; separators are already
/// normalized by [pathConv].
@visibleForTesting
String foldMatchSegment(String segment) => segment.toLowerCase();

/// Absolute match segments of a storage's base path (via [pathConv], so a UNC
/// shortcut's single `\\server\share` base expands to two comparable segments).
List<String> storageMatchSegments(Storage storage) =>
    pathConv(storage.basePath.join('/'));

/// A dropped path resolved against a storage. [relative] is the base-relative
/// segment list (empty = the storage root itself).
@immutable
class DragDropStorageMatch {
  const DragDropStorageMatch({required this.storage, required this.relative});

  final Storage storage;
  final List<String> relative;
}

/// Longest segment-prefix match of [absoluteSegments] against [storages].
///
/// Comparison is segment-wise and case-insensitive, so a dropped
/// `d:\movies\x.mkv` still matches the `D:` drive. The longest base wins, so a
/// UNC shortcut (`\\server\share`) beats a drive mapping when both could match.
/// Returns null when no storage's base path is a prefix.
DragDropStorageMatch? matchDropStorage({
  required List<String> absoluteSegments,
  required Iterable<Storage> storages,
}) {
  DragDropStorageMatch? best;
  var bestLength = -1;
  for (final storage in storages) {
    final base = storageMatchSegments(storage);
    if (base.isEmpty || base.length > absoluteSegments.length) continue;
    var isPrefix = true;
    for (var i = 0; i < base.length; i++) {
      if (foldMatchSegment(base[i]) !=
          foldMatchSegment(absoluteSegments[i])) {
        isPrefix = false;
        break;
      }
    }
    if (!isPrefix) continue;
    if (base.length > bestLength) {
      bestLength = base.length;
      best = DragDropStorageMatch(
        storage: storage,
        relative: absoluteSegments.sublist(base.length),
      );
    }
  }
  return best;
}

/// Raw storage path (base-prefixed) for [relative], matching the form the
/// storage browser and scanner use. Empty [relative] yields the storage base.
String rawStoragePath(Storage storage, List<String> relative) {
  final base = storage.basePath.join('/');
  if (relative.isEmpty) return base;
  return '$base/${relative.join('/')}';
}

/// A dropped directory, resolved to its owner storage.
@immutable
class DragDropResolvedDir {
  const DragDropResolvedDir({
    required this.storageId,
    required this.path,
    required this.relative,
  });

  final String storageId;

  /// Spec path (base-prefixed raw path); empty string = storage root.
  final String path;

  /// Base-relative segments (used for de-duplication / coverage checks).
  final List<String> relative;
}

/// A dropped media file, resolved to its owner storage.
@immutable
class DragDropResolvedFile {
  const DragDropResolvedFile({
    required this.rawPath,
    required this.storageId,
    required this.path,
    required this.relative,
    required this.contentType,
  });

  final String rawPath;
  final String storageId;

  /// Base-prefixed raw path (used to build the DB node row).
  final String path;

  /// Base-relative segments (includes the file name).
  final List<String> relative;

  final ContentType contentType;
}

/// De-duplicates directory specs by (storage, path), preserving first-seen
/// order.
List<DragDropResolvedDir> dedupeDropDirs(List<DragDropResolvedDir> dirs) {
  final seen = <String>{};
  final out = <DragDropResolvedDir>[];
  for (final dir in dirs) {
    if (seen.add('${dir.storageId}\u0000${dir.path}')) out.add(dir);
  }
  return out;
}

/// Removes files already covered by a dropped directory (same storage and under
/// its subtree) so a file dropped alongside its parent folder never appears
/// twice in the queue.
List<DragDropResolvedFile> dropFilesNotCoveredByDirs({
  required List<DragDropResolvedFile> files,
  required List<DragDropResolvedDir> dirs,
}) {
  return [
    for (final file in files)
      if (!dirs.any((dir) => _coveredBy(file, dir))) file,
  ];
}

bool _coveredBy(DragDropResolvedFile file, DragDropResolvedDir dir) {
  if (file.storageId != dir.storageId) return false;
  if (dir.relative.length > file.relative.length) return false;
  for (var i = 0; i < dir.relative.length; i++) {
    if (foldMatchSegment(dir.relative[i]) !=
        foldMatchSegment(file.relative[i])) {
      return false;
    }
  }
  return true;
}

/// Result of the browse-scope restriction pre-check.
@immutable
class DragDropScopeReport {
  const DragDropScopeReport({
    required this.restricted,
    required this.hasScopedMedia,
  });

  /// True when the requested scope hides at least one playable item.
  final bool restricted;

  /// True when at least one in-scope item survives (dirs or files).
  final bool hasScopedMedia;
}

/// Counts playable file nodes under a directory spec for a media-type filter.
typedef DropDirCount = Future<int> Function(
  DragDropResolvedDir dir,
  List<MediaType>? mediaTypes,
);

/// Browse-scope pre-check: a directory is restricted when its unscoped
/// playable count exceeds its scoped count; a file is restricted when its own
/// type is out of scope.
Future<DragDropScopeReport> evaluateDropScopeRestriction({
  required List<FileItem> files,
  required List<DragDropResolvedDir> dirs,
  required BrowseMediaScope scope,
  required DropDirCount countDir,
}) async {
  final allPlayable = const <MediaType>[MediaType.video, MediaType.audio];
  final scoped = scopeMediaTypes(scope) ?? allPlayable;
  var restricted = false;
  var hasScopedMedia = false;

  for (final dir in dirs) {
    final full = await countDir(dir, allPlayable);
    final within = await countDir(dir, scoped);
    if (within > 0) hasScopedMedia = true;
    if (full > within) restricted = true;
  }

  var inScopeFiles = 0;
  for (final file in files) {
    if (file.matchesBrowseScope(scope)) {
      inScopeFiles++;
    } else {
      restricted = true;
    }
  }
  if (inScopeFiles > 0) hasScopedMedia = true;

  return DragDropScopeReport(
    restricted: restricted,
    hasScopedMedia: hasScopedMedia,
  );
}

/// Routes a desktop drag-and-drop of files/directories into the
/// scenario-override playback path.
///
/// Dropped DIRECTORIES become recursive folder sources (their subtree is
/// scanned through the shared scan gate first); dropped FILES become explicit
/// items (indexed directly so the playability pre-check has DB rows). The
/// current browse media scope narrows what actually plays, with a suppressive
/// notice the first time content is filtered. [zone] selects the action: the
/// top strip appends to the queue, the rest overrides and plays. The handler is
/// self-contained so the scan gate's resume closure can simply re-run it with
/// the same paths and zone.
abstract final class DragDropPlayHandler {
  const DragDropPlayHandler._();

  static Future<void> handle(
    BuildContext context,
    List<String> rawPaths, {
    required DragDropZone zone,
  }) async {
    if (rawPaths.isEmpty) return;

    final classified = <_ClassifiedDrop>[];
    for (final raw in rawPaths) {
      var exists = false;
      var isDirectory = false;
      try {
        final type = await FileSystemEntity.type(raw);
        exists = type != FileSystemEntityType.notFound;
        isDirectory = type == FileSystemEntityType.directory;
      } catch (_) {
        exists = false;
      }
      final kind = classifyDropKind(
        exists: exists,
        isDirectory: isDirectory,
      );
      if (kind == DragDropEntryKind.ignored) continue;
      final contentType = kind == DragDropEntryKind.file
          ? checkContentType(raw)
          : ContentType.other;
      if (kind == DragDropEntryKind.file &&
          !isPlayableContentType(contentType)) {
        continue;
      }
      classified.add(_ClassifiedDrop(
        rawPath: raw,
        kind: kind,
        contentType: contentType,
      ));
    }
    if (classified.isEmpty) return;

    final known = <Storage>[];
    final seenIds = <String>{};
    void addKnown(Storage storage) {
      if (seenIds.add(storage.id)) known.add(storage);
    }

    if (!context.mounted) return;
    try {
      for (final storage in await getLocalStorages(context)) {
        addKnown(storage);
      }
    } catch (_) {
      // Enumerating drives is best-effort; fall through to store entries.
    }
    for (final storage in useStorageStore().state.storages) {
      addKnown(storage);
    }

    final dirs = <DragDropResolvedDir>[];
    final files = <DragDropResolvedFile>[];
    final toPersist = <Storage>[];

    for (final entry in classified) {
      final segments = pathConv(entry.rawPath);
      if (segments.isEmpty) continue;
      var match = matchDropStorage(
        absoluteSegments: segments,
        storages: known,
      );
      if (match == null) {
        match = await _ephemeralMatch(entry, segments);
        if (match == null) continue;
        addKnown(match.storage);
      }
      final storage = match.storage;
      final relative = match.relative;
      if (useStorageStore().findById(storage.id) == null &&
          !toPersist.any((s) => s.id == storage.id)) {
        toPersist.add(storage);
      }
      if (entry.kind == DragDropEntryKind.directory) {
        dirs.add(DragDropResolvedDir(
          storageId: storage.id,
          path: relative.isEmpty ? '' : rawStoragePath(storage, relative),
          relative: relative,
        ));
      } else {
        files.add(DragDropResolvedFile(
          rawPath: entry.rawPath,
          storageId: storage.id,
          path: rawStoragePath(storage, relative),
          relative: relative,
          contentType: entry.contentType,
        ));
      }
    }

    // The scan gate resolves its storage via the store (`_startScanFor`), so
    // every storage feeding a scan must be persisted before the gate runs.
    for (final storage in toPersist) {
      await _persistStorage(storage);
    }

    final uniqueDirs = dedupeDropDirs(dirs);
    final explicit = dropFilesNotCoveredByDirs(
      files: files,
      dirs: uniqueDirs,
    );

    final fileItems = <FileItem>[];
    for (final file in explicit) {
      final item = await _indexFile(file);
      if (item != null) fileItems.add(item);
    }

    if (uniqueDirs.isNotEmpty) {
      final specs = <ScenarioSourceSpec>[
        for (final dir in uniqueDirs)
          (storageId: dir.storageId, path: dir.path, recursive: true),
      ];
      if (!context.mounted) return;
      final proceed = await ensureDirsScannedWithPendingPlay(
        context,
        specs,
        playOnScanNow: () => handle(context, rawPaths, zone: zone),
      );
      if (!proceed) return;
    }

    if (!context.mounted) return;

    final scope = currentBrowseMediaScope();
    final report = await evaluateDropScopeRestriction(
      files: fileItems,
      dirs: uniqueDirs,
      scope: scope,
      countDir: _countDirInDb,
    );
    if (!context.mounted) return;

    if (report.restricted) {
      final t = getLocalizations(context);
      final proceed = await showConfirmSuppressibleDialog(
        context,
        warningId: kWarningDragDropScopeRestricted,
        title: t.dragdrop_scope_restricted_title,
        message: t.dragdrop_scope_restricted_body,
        confirmLabel: t.dragdrop_scope_restricted_continue,
        cancelLabel: t.cancel,
        defaultDontAsk: true,
      );
      // Suppressed ids auto-confirm (silent continue); the in-scope subset is
      // still what plays. When nothing survives, stop without a misleading
      // force-append prompt.
      if (!proceed || !context.mounted) return;
      if (!report.hasScopedMedia) return;
    }

    if (!context.mounted) return;
    final inScopeFiles = <FileItem>[
      for (final file in fileItems)
        if (file.matchesBrowseScope(scope)) file,
    ];
    final specs = <ScenarioSourceSpec>[
      for (final dir in uniqueDirs)
        (storageId: dir.storageId, path: dir.path, recursive: true),
    ];

    // Top zone: append to the queue (same semantics as storagedb/lib "append to
    // play"), without starting playback. Bottom zone: override the workspace
    // and play immediately.
    if (zone == DragDropZone.append) {
      await ScenarioAppendActions.appendToDefaultScenario(
        inScopeFiles,
        directories: specs,
      );
      return;
    }

    await ScenarioPlaybackActions.runPlayActionWithNoMediaConfirm(
      context,
      action: ({bool force = false}) =>
          ScenarioOverrideActions.playSelectionInDefaultScenario(
        files: inScopeFiles,
        directories: specs,
        sortField: ScenarioSortField.name,
        sortDirection: SortDirection.asc,
        force: force,
      ),
    );
  }

  /// Fallback for a path that no enumerated/store storage owns: root an
  /// ephemeral local storage at the dropped directory (or the file's parent).
  static Future<DragDropStorageMatch?> _ephemeralMatch(
    _ClassifiedDrop entry,
    List<String> segments,
  ) async {
    final List<String> relative;
    if (entry.kind == DragDropEntryKind.directory) {
      relative = const [];
    } else {
      if (segments.length < 2) return null;
      relative = [segments.last];
    }
    final base = entry.kind == DragDropEntryKind.directory
        ? segments
        : segments.sublist(0, segments.length - 1);
    if (base.isEmpty) return null;
    final storage = makeLocalStorage(
      type: StorageType.internal,
      name: base.last,
      basePath: base,
      volumeId: await VolumeIdentity.of(base.join('/')),
    );
    return DragDropStorageMatch(storage: storage, relative: relative);
  }

  static Future<void> _persistStorage(Storage storage) async {
    try {
      await DbModule.storageRepo.updateInsertStorage(storage);
    } catch (_) {
      // A failed DB write must not abort playback: the in-memory store entry
      // still lets the scan gate resolve the storage.
    }
    await useStorageStore().addStorage(storage);
  }

  /// Indexes one dropped file so the playability pre-check and the explicit
  /// resolver find a DB row — a light, non-recursive substitute for scanning
  /// the whole parent directory.
  static Future<FileItem?> _indexFile(DragDropResolvedFile file) async {
    if (file.relative.isEmpty) return null;
    final name = file.relative.last;
    var size = 0;
    DateTime? modified;
    try {
      final stat = await File(file.rawPath).stat();
      size = stat.size;
      modified = stat.modified;
    } catch (_) {
      // A stat failure still indexes a zero-size row; playback will surface
      // any real open error.
    }

    final nodeSegments =
        file.path.split('/').where((s) => s.isNotEmpty).toList();
    final canonical = canonicalDbPath(file.path);
    try {
      await DbModule.mediaNodesDao.upsertNode(MediaNode.file(
        id: '${file.storageId}:$canonical',
        storageId: file.storageId,
        path: nodeSegments,
        parentPath: nodeSegments.length > 1
            ? nodeSegments.sublist(0, nodeSegments.length - 1).join('/')
            : null,
        pathDepth: nodeSegments.length,
        name: name,
        mediaType: file.contentType == ContentType.audio
            ? MediaType.audio
            : MediaType.video,
        sizeInBytes: size,
        modifiedAt: modified,
        uri: isSafPath(file.rawPath) ? file.rawPath : null,
        isPresent: true,
      ));
    } catch (_) {
      return null;
    }

    return FileItem(
      storageId: file.storageId,
      name: name,
      uri: file.rawPath,
      path: pathConv(file.rawPath),
      isDir: false,
      size: size,
      lastModified: modified,
      type: file.contentType,
    );
  }

  static Future<int> _countDirInDb(
    DragDropResolvedDir dir,
    List<MediaType>? mediaTypes,
  ) async {
    final result = await DbModule.mediaNodeRepo.getPagedNodesForSources(
      sources: [
        (
          storageId: dir.storageId,
          path: dir.path.isEmpty ? null : dir.path,
          kind: MediaSourceKind.directory,
          recursive: true,
          scenarioSourceId: null,
        ),
      ],
      nodeKind: MediaNodeKind.file,
      mediaTypes: mediaTypes,
      page: 0,
      pageSize: 1,
    );
    return result.totalItems;
  }
}

@immutable
class _ClassifiedDrop {
  const _ClassifiedDrop({
    required this.rawPath,
    required this.kind,
    required this.contentType,
  });

  final String rawPath;
  final DragDropEntryKind kind;
  final ContentType contentType;
}
