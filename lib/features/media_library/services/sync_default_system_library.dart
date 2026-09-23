import 'package:iris/features/media_library/model/enum/media_lib_sources.dart';
import 'package:iris/features/media_library/model/media_lib/media_library.dart';
import 'package:iris/features/media_library/model/media_lib/media_library_source.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/storages/storage.dart';

const String systemLibraryId = 'local_lib';

Future<void> syncDefaultSystemLibrary() async {
  final facade = DbModule.mediaFacade;

  final existing = await facade.getLibraryById(systemLibraryId);

  // ----------------------------------------
  // ensure library exists
  // ----------------------------------------

  if (existing == null) {
    final now = DateTime.now();

    await facade.saveLibrary(
      MediaLibrary(
        id: systemLibraryId,
        name: 'System Library',
        type: MediaLibraryType.system,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  // ----------------------------------------
  // ensure sources exist
  // ----------------------------------------

  final storages = await DbModule.storageRepo.getStorages();

  final localStorages = storages.where((s) {
    return s.type == StorageType.internal ||
        s.type == StorageType.network ||
        s.type == StorageType.usb ||
        s.type == StorageType.sdcard;
  }).toList();

  final existingSources = await facade.getSources(systemLibraryId);

  final existingByStorageId = {
    for (final source in existingSources)
      if (source.path == null) source.storageId: source,
  };

  // only ADD missing sources
  // NEVER remove old ones automatically

  for (final storage in localStorages) {
    if (!existingByStorageId.containsKey(storage.id)) {
      await facade.saveSource(
        MediaLibrarySource(
          id: 0,
          libraryId: systemLibraryId,
          storageId: storage.id,
          path: null,
          kind: MediaSourceKind.storage,
        ),
      );
    }
  }
}
