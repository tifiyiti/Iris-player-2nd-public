import 'package:iris/features/background_playback/engine/background_queue_logic.dart';
import 'package:iris/features/background_playback/model/db/repositories/bg_source_rule_repository.dart';
import 'package:iris/features/background_playback/model/enum/bg_source_rule_kind.dart';
import 'package:iris/features/background_playback/model/enum/bg_source_sort_field.dart';
import 'package:iris/features/background_playback/model/source/bg_source_rule.dart';
import 'package:iris/features/background_playback/services/background_file_builder.dart';
import 'package:iris/features/background_playback/store/bg_source_prefs.dart';
import 'package:iris/features/media_library/model/db/repositories/sub/media_node_repository.dart';
import 'package:iris/features/media_library/model/enum/basic_enum.dart';
import 'package:iris/features/media_library/model/enum/media_node.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/tag_play/model/db/repositories/tag_play_repository.dart';
import 'package:iris/features/tag_play/model/enum/tag_system_kind.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/file.dart';
import 'package:iris/utils/dir_match.dart';
import 'package:iris/utils/path_conv.dart';

/// Outcome of resolving the enabled 副音 source rules.
///
/// [enabledRuleCount] lets the caller distinguish "rules matched nothing"
/// from "no active source at all" (which triggers the zero-active fallback to
/// the built-in library pure-tag source).
class BgSourceResolution {
  const BgSourceResolution({
    required this.files,
    required this.enabledRuleCount,
  });

  final List<FileItem> files;
  final int enabledRuleCount;

  bool get hasActiveRules => enabledRuleCount > 0;
}

/// Multi-rule 副音 candidate resolution.
///
/// Rules are read from the `bg_source_rules` table (pinned-first, then
/// insertion order) and honored top-to-bottom. Every rule resolves to real
/// single files only; vanished media is silently skipped — a dead rule never
/// kills the subsystem. Cross-rule dedupe is applied ONLY when the global
/// [BgSourcePrefs.autoDedupe] switch is on (default off).
///
/// Resolution runs on launch/refresh only (never per frame): directory rules
/// share ONE bounded library snapshot so a phone never re-scans per rule.
class BackgroundSourceResolver {
  BackgroundSourceResolver({
    TagPlayRepository? tagRepo,
    MediaNodeRepository? nodeRepo,
    BgSourceRuleRepository? ruleRepo,
  })  : tagRepo = tagRepo ?? DbModule.tagPlayRepo,
        nodeRepo = nodeRepo ?? DbModule.mediaNodeRepo,
        ruleRepo = ruleRepo ?? DbModule.bgSourceRuleRepo;

  static const int defaultCap = 400;

  /// Bounded scan for directory rules — enough for thousands of candidates
  /// without ever materializing a 50w-file library.
  static const int maxScanItems = 20000;

  /// Node-probe batch for tag rules sorted by tag time: members are light, so
  /// order them first and probe in chunks, stopping at the cap — a huge tag
  /// must not pay a probe per member just to keep a bounded head.
  static const int tagProbeBatch = 256;

  final TagPlayRepository tagRepo;
  final MediaNodeRepository nodeRepo;
  final BgSourceRuleRepository ruleRepo;

  Future<BgSourceResolution> resolve({
    int cap = defaultCap,
    bool? dedupe,
  }) async {
    final rules = await ruleRepo.loadRules();
    final enabled = [for (final r in rules) if (r.enabled) r];
    if (enabled.isEmpty) {
      return const BgSourceResolution(files: [], enabledRuleCount: 0);
    }

    final doDedupe = dedupe ?? await BgSourcePrefs.autoDedupe();
    _LibrarySnapshot? snapshot;
    final out = <FileItem>[];
    final seen = <String>{};

    for (final rule in enabled) {
      if (out.length >= cap) break;
      final remaining = cap - out.length;
      final List<FileItem> resolved;
      switch (rule.kind) {
        case BgSourceRuleKind.tag:
          resolved = await _resolveTag(rule, remaining);
        case BgSourceRuleKind.directory:
          snapshot ??= await _loadLibrarySnapshot();
          resolved = await _resolveDirectory(rule, snapshot, remaining);
        case BgSourceRuleKind.file:
          resolved = await _resolveFile(rule);
      }
      for (final file in resolved) {
        if (doDedupe && !seen.add(backgroundMediaKey(file))) continue;
        out.add(file);
        if (out.length >= cap) break;
      }
    }

    return BgSourceResolution(files: out, enabledRuleCount: enabled.length);
  }

  // ── tag ──

  Future<List<FileItem>> _resolveTag(BgSourceRule rule, int cap) async {
    final tagId = rule.tagId ?? await _reservedTagId();
    if (tagId == null) return const [];
    final members = await tagRepo.activeMembersOf(tagId);
    if (members.isEmpty) return const [];
    if (rule.sortField == BgSourceSortField.tagAddedAt) {
      // Tag-time order needs no node data to sequence: probe in bounded
      // batches and stop at the cap. Output is identical to sort-all-then-take
      // (same order, same tiebreak, vanished files still skipped).
      final ordered = List.of(members)
        ..sort((a, b) {
          final c = a.addedAt.compareTo(b.addedAt);
          if (c != 0) {
            return rule.sortDirection == SortDirection.asc ? c : -c;
          }
          return a.mediaKey.compareTo(b.mediaKey);
        });
      final files = <FileItem>[];
      for (var i = 0; i < ordered.length && files.length < cap; i += tagProbeBatch) {
        final batch = ordered.skip(i).take(tagProbeBatch);
        final fileByKey = await _filesByMemberKey(
            {for (final m in batch) m.mediaKey});
        for (final m in batch) {
          if (files.length >= cap) break;
          final file = fileByKey[m.mediaKey];
          if (file != null) files.add(file);
        }
      }
      return files;
    }
    final fileByKey =
        await _filesByMemberKey({for (final m in members) m.mediaKey});
    final entries = <_CandidateEntry>[];
    for (final member in members) {
      final file = fileByKey[member.mediaKey];
      if (file == null) continue;
      entries.add(_CandidateEntry(file, tagAddedAt: member.addedAt));
    }
    return _sorted(entries, rule, cap);
  }

  /// Resolves existing file nodes for tag member keys to playback files,
  /// silently skipping vanished rows.
  Future<Map<String, FileItem>> _filesByMemberKey(Set<String> keys) async {
    final nodes = await nodeRepo.nodesByMediaKeys(keys);
    final fileByKey = <String, FileItem>{};
    for (final node in nodes) {
      final file = node.maybeMap(file: (f) => f, orElse: () => null);
      if (file == null) continue;
      fileByKey[_mediaKey(file)] = backgroundFileItemFromMediaFile(file);
    }
    return fileByKey;
  }

  Future<int?> _reservedTagId() async {
    final tags = await tagRepo.tags();
    for (final tag in tags) {
      if (tag.systemKind == TagSystemKind.backgroundVoiceCandidate) {
        return tag.id;
      }
    }
    return null;
  }

  // ── directory ──

  Future<List<FileItem>> _resolveDirectory(
    BgSourceRule rule,
    _LibrarySnapshot snapshot,
    int cap,
  ) async {
    Set<String>? tagKeys;
    if (rule.tagFilterEnabled) {
      final tagId = rule.filterTagId;
      if (tagId == null) return const [];
      final members = await tagRepo.activeMembersOf(tagId);
      if (members.isEmpty) return const [];
      tagKeys = {for (final m in members) m.mediaKey};
    }

    final entries = <_CandidateEntry>[];
    for (final entry in snapshot.entries) {
      if (!dirRuleMatchesFile(
        mode: rule.matchMode,
        paths: rule.paths,
        patterns: rule.patterns,
        fullPath: entry.fullPath,
        parentPath: entry.parentPath,
      )) {
        continue;
      }
      if (tagKeys != null && !tagKeys.contains(entry.mediaKey)) continue;
      entries.add(entry);
    }
    return _sorted(entries, rule, cap);
  }

  /// Pages the whole media table once per resolution (bounded by
  /// [maxScanItems]) so every directory rule shares one scan.
  Future<_LibrarySnapshot> _loadLibrarySnapshot() async {
    final entries = <_CandidateEntry>[];
    var page = 1;
    while (entries.length < maxScanItems) {
      final result = await nodeRepo.getAllMedia(
        page: page,
        pageSize: 1000,
        mediaTypes: const [MediaType.video, MediaType.audio],
        sortField: MediaSortField.name,
        sortDirection: SortDirection.asc,
      );
      final items = result.items;
      for (final node in items) {
        final file = node.maybeMap(file: (f) => f, orElse: () => null);
        if (file == null) continue;
        entries.add(_CandidateEntry(
          backgroundFileItemFromMediaFile(file),
          tagAddedAt: null,
          storageId: file.storageId,
          fullPath: file.path.join('/'),
          parentPath: canonicalPath(file.parentPath ?? ''),
          durationMs: file.durationMs,
        ));
        if (entries.length >= maxScanItems) break;
      }
      if (items.length < 1000 || page >= 50) break;
      page++;
    }
    return _LibrarySnapshot(entries);
  }

  // ── file ──

  Future<List<FileItem>> _resolveFile(BgSourceRule rule) async {
    final storageId = rule.fileStorageId;
    final filePath = rule.filePath;
    if (storageId == null || filePath == null || filePath.isEmpty) {
      return const [];
    }
    final segments =
        filePath.split('/').where((s) => s.isNotEmpty).toList(growable: false);
    if (segments.isEmpty) return const [];
    final node = await nodeRepo.getNodeByPath(
      storageId: storageId,
      path: segments,
    );
    final file = node?.maybeMap(file: (f) => f, orElse: () => null);
    if (file == null) return const [];
    return [backgroundFileItemFromMediaFile(file)];
  }

  // ── ordering ──

  List<FileItem> _sorted(
    List<_CandidateEntry> entries,
    BgSourceRule rule,
    int cap,
  ) {
    final factor =
        rule.sortDirection == SortDirection.asc ? 1 : -1;
    // Decorate once: the comparator below used to recompute the sort value
    // (including `toLowerCase()` allocations) on EVERY comparison — O(n log n)
    // garbage for a large snapshot. Semantics are unchanged.
    final decorated = [
      for (final e in entries) (entry: e, key: _valueOf(e, rule.sortField)),
    ];
    decorated.sort((a, b) {
      final av = a.key;
      final bv = b.key;
      // Unknown/absent values always sort LAST, regardless of direction.
      if (av == null && bv == null) {
        return a.entry.mediaKey.compareTo(b.entry.mediaKey);
      }
      if (av == null) return 1;
      if (bv == null) return -1;
      final c = av.compareTo(bv);
      if (c != 0) return factor * c;
      return a.entry.mediaKey.compareTo(b.entry.mediaKey);
    });

    return [
      for (final d in decorated.take(cap)) d.entry.file,
    ];
  }

  Comparable<Object>? _valueOf(_CandidateEntry e, BgSourceSortField field) =>
      switch (field) {
        BgSourceSortField.tagAddedAt => e.tagAddedAt,
        BgSourceSortField.name => e.file.name.toLowerCase(),
        BgSourceSortField.path => e.file.path.join('/').toLowerCase(),
        BgSourceSortField.duration => e.durationMs,
        BgSourceSortField.modifiedAt => e.file.lastModified,
        BgSourceSortField.size => e.file.size,
      };

  static String _mediaKey(MediaFile file) =>
      canonicalKey(file.storageId, file.path.join('/'));
}

class _LibrarySnapshot {
  const _LibrarySnapshot(this.entries);
  final List<_CandidateEntry> entries;
}

class _CandidateEntry {
  _CandidateEntry(
    this.file, {
    required this.tagAddedAt,
    String? storageId,
    String? fullPath,
    String? parentPath,
    this.durationMs,
  })  : mediaKey = canonicalKey(
          storageId ?? file.storageId,
          fullPath ?? file.path.join('/'),
        ),
        _fullPath = fullPath ?? file.path.join('/'),
        _parentPath = parentPath ?? '';

  final FileItem file;
  final DateTime? tagAddedAt;
  final int? durationMs;
  final String mediaKey;
  final String _fullPath;
  final String _parentPath;

  String get fullPath => _fullPath;
  String get parentPath => _parentPath;
}
