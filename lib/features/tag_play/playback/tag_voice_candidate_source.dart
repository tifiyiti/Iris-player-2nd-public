import 'package:iris/features/background_playback/services/background_candidate_source.dart';
import 'package:iris/features/background_playback/services/background_file_builder.dart';
import 'package:iris/features/media_library/model/db/repositories/sub/media_node_repository.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/tag_play/model/db/repositories/tag_play_repository.dart';
import 'package:iris/features/tag_play/model/enum/tag_system_kind.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/file.dart';
import 'package:iris/utils/path_conv.dart' show canonicalKey;

/// 「副音备选」reserved tag → real single-file candidate source.
///
/// The background playback core only knows [BackgroundCandidateSource]; this
/// adapter is tag_play's implementation of it (tag_play owns its own DB, the
/// background feature never touches video_tags directly).
///
/// Members are canonical `(storageId, path)` strings; each is resolved to a
/// real media node row (vanished files are silently skipped) and converted to
/// the [FileItem] the playback side consumes via the shared
/// [backgroundFileItemFromMediaFile] builder.
class TagVoiceCandidateSource implements BackgroundCandidateSource {
  TagVoiceCandidateSource({
    TagPlayRepository? tagRepo,
    MediaNodeRepository? nodeRepo,
  })  : _tagRepo = tagRepo ?? DbModule.tagPlayRepo,
        _nodeRepo = nodeRepo ?? DbModule.mediaNodeRepo;

  final TagPlayRepository _tagRepo;
  final MediaNodeRepository _nodeRepo;

  @override
  String get id => 'tag:backgroundVoiceCandidate';

  /// Node-probe batch: members are light, so order them first and probe in
  /// chunks, stopping at the cap — a huge tag must not pay a probe per member
  /// just to keep the newest bounded head.
  static const int probeBatch = 256;

  @override
  Future<List<FileItem>> resolveCandidates({int cap = 400}) async {
    final all = await _tagRepo.tags();
    final tag = all
        .where((t) => t.systemKind == TagSystemKind.backgroundVoiceCandidate)
        .firstOrNull;
    if (tag == null) return const [];

    final members = await _tagRepo.activeMembersOf(tag.id);
    if (members.isEmpty) return const [];
    // Members are not guaranteed ordered by the DAO — sort explicitly by
    // tag time (newest first), then probe in bounded batches so only the
    // head's nodes are ever loaded.
    final ordered = List.of(members)
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    final files = <FileItem>[];
    for (var i = 0; i < ordered.length && files.length < cap; i += probeBatch) {
      final batch = ordered.skip(i).take(probeBatch);
      final nodes = await _nodeRepo.nodesByMediaKeys(
        {for (final m in batch) m.mediaKey},
      );
      final fileByKey = <String, FileItem>{};
      for (final node in nodes) {
        final fileNode = node.maybeMap(file: (f) => f, orElse: () => null);
        if (fileNode == null) continue;
        fileByKey[canonicalKey(fileNode.storageId, fileNode.path.join('/'))] =
            backgroundFileItemFromMediaFile(fileNode);
      }
      // Drop vanished files, keep the tag-time order.
      for (final member in batch) {
        if (files.length >= cap) break;
        final file = fileByKey[member.mediaKey];
        if (file != null) files.add(file);
      }
    }
    return files;
  }
}
