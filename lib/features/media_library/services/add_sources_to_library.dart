import 'package:iris/features/media_library/model/media_lib/media_library_source.dart';
import 'package:iris/models/db/db_module.dart';

/// Adds [sources] to the target library, deduplicating by (storageId, path).
///
/// Returns the count of sources actually added (skipped duplicates are excluded).
Future<int> addSourcesToLibrary({
  required String targetLibraryId,
  required List<MediaLibrarySource> sources,
}) async {
  final existing = await DbModule.sourcesRepository.getSources(targetLibraryId);
  final existingKeys = existing
      .map((s) => '${s.storageId}:${s.path?.join('/')}')
      .toSet();

  var added = 0;
  for (final source in sources) {
    final key = '${source.storageId}:${source.path?.join('/')}';
    if (existingKeys.contains(key)) continue;

    await DbModule.sourcesRepository.addSource(
      source.copyWith(libraryId: targetLibraryId),
    );
    added++;
  }
  return added;
}
