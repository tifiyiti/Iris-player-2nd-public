import 'package:drift/drift.dart';
import 'package:iris/features/media_library/model/media_lib/media_library.dart';
import 'package:iris/models/db/app_database.dart';

extension MediaLibraryDriftAdapter on MediaLibrary {
  static MediaLibrary fromDb(MediaLibsTableData row) {
    return MediaLibrary(
      id: row.id,
      name: row.name,
      type: MediaLibraryType.values[row.libType],
      createdAt: row.createdAt ?? DateTime.now(),
      updatedAt: row.updatedAt ?? DateTime.now(),
    );
  }

  MediaLibsTableCompanion toCompanion() {
    return MediaLibsTableCompanion.insert(
      id: id,
      name: name,
      libType: type.index,
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }
}

extension MediaLibraryX on MediaLibrary {
  bool get isSystem => type == MediaLibraryType.system;

  bool get isUser => type == MediaLibraryType.user;
}
