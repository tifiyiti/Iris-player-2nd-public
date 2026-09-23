import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/enum/media_lib_sources.dart';
import 'package:iris/features/media_library/model/enum/media_node.dart';
import 'package:iris/features/media_library/services/media_node_sync_service.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/utils/path_conv.dart';

import 'helpers/sqlite3_loader.dart';

/// The DB (`media_nodes.parent_path` / `path`) speaks the CANONICAL, slash-free
/// dialect — the storage root is `''`/NULL and subfolders are `anime`. The
/// files-paged browser used to hand `MediaNodeSyncService.syncDirectory` its RAW
/// storage-relative path (`['/']` for a WebDAV root), so rows landed as
/// `parent_path = '/'` / `path = '//name'` and every scenario scope lookup
/// missed → "no playable media in folder '/'" on tap-to-play.
Storage _webdav() => Storage.webdav(
      id: 's1',
      name: 'nas',
      host: '192.168.1.4',
      basePath: const <String>['/'],
      port: '8090',
      username: 'u',
      password: 'p',
      https: false,
    );

FileItem _video(String name) => FileItem(
      storageId: 's1',
      storageType: StorageType.webdav,
      name: name,
      uri: 'http://192.168.1.4:8090/$name',
      path: <String>[name],
      type: ContentType.video,
      size: 1,
    );

FileItem _dir(String name) => FileItem(
      storageId: 's1',
      storageType: StorageType.webdav,
      name: name,
      uri: 'http://192.168.1.4:8090/$name',
      path: <String>[name],
      isDir: true,
      type: ContentType.other,
    );

/// Counts the playable files the scenario pre-check would see for a directory
/// source. [path] is passed exactly as `playFolderScopeInDefaultScenario` does.
Future<int> _playableFilesUnder(String? path, {required bool recursive}) async {
  final res = await DbModule.mediaNodeRepo.getPagedNodesForSources(
    sources: [
      (
        storageId: 's1',
        path: path,
        kind: MediaSourceKind.directory,
        recursive: recursive,
        scenarioSourceId: null,
      ),
    ],
    nodeKind: MediaNodeKind.file,
    page: 0,
    pageSize: 10,
  );
  return res.totalItems;
}

Future<void> _clearNodes() =>
    DbModule.mediaNodesDao.delete(DbModule.mediaNodesDao.mediaNodesTable).go();

void main() {
  ensureSqlite3Loaded();

  setUpAll(() async {
    await DbModule.init(AppDatabase(NativeDatabase.memory()));
  });

  setUp(_clearNodes);

  test('storage root syncs canonical AND is found by the play pre-check',
      () async {
    await MediaNodeSyncService().syncDirectory(
      storage: _webdav(),
      items: <FileItem>[_video('a.mp4'), _dir('anime')],
      // The RAW form the files-paged browser used to pass.
      dirPath: const <String>['/'],
    );

    // Stored canonically (no leading-slash segment).
    expect(
      await DbModule.mediaNodeRepo.getNodeByPath(
        storageId: 's1',
        path: const <String>['a.mp4'],
      ),
      isNotNull,
    );
    // The pre-check with folderPath '/' must hit (this was 0 before the fix).
    expect(await _playableFilesUnder('/', recursive: false), 1);
  });

  test('subfolder syncs canonical and is matchable with either slash form',
      () async {
    await MediaNodeSyncService().syncDirectory(
      storage: _webdav(),
      items: <FileItem>[_video('b.mp4')],
      dirPath: const <String>['/', 'anime'],
    );

    expect(
      await DbModule.mediaNodeRepo.getNodeByPath(
        storageId: 's1',
        path: const <String>['anime', 'b.mp4'],
      ),
      isNotNull,
    );
    expect(await _playableFilesUnder('anime', recursive: false), 1);
    expect(await _playableFilesUnder('/anime', recursive: false), 1);
  });

  test('raw and canonical dirPath forms produce the same lookup result',
      () async {
    await MediaNodeSyncService().syncDirectory(
      storage: _webdav(),
      items: <FileItem>[_video('a.mp4')],
      dirPath: const <String>['/'],
    );
    expect(await _playableFilesUnder('/', recursive: false), 1);

    await _clearNodes();
    await MediaNodeSyncService().syncDirectory(
      storage: _webdav(),
      items: <FileItem>[_video('a.mp4')],
      dirPath: const <String>[],
    );
    expect(await _playableFilesUnder('/', recursive: false), 1);
  });

  test('canonicalDbPath keeps treating "/" as the storage root', () {
    expect(canonicalDbPath('/'), '');
    expect(canonicalDbPath('//anime'), 'anime');
  });
}
