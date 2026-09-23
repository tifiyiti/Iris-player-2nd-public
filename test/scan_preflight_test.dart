import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/scan/service/scan_preflight.dart';
import 'package:iris/features/webdav_discovery/services/webdav_connect_coordinator.dart';
import 'package:iris/models/enums/storage_list_error.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/storages/file_list_result.dart';
import 'package:iris/models/storages/storage.dart';

// Entry-side remote-connect handling for the storagedb Storage-tab scan:
// an unreachable/unauthorized host is classified up front, never mistaken for
// an empty directory (which would purge the DB snapshot).
void main() {
  Storage local() => Storage.local(
        id: 'l1',
        type: StorageType.internal,
        name: 'Local',
        basePath: const ['/tmp'],
      );

  FTPStorage ftp() => Storage.ftp(
        id: 'ftp1',
        name: 'FTP',
        host: '10.0.0.2',
        basePath: const [''],
        port: '21',
        username: 'u',
        password: 'p',
      ) as FTPStorage;

  WebDAVStorage wildcard({List<String> resolvedHosts = const []}) =>
      Storage.webdav(
        id: 'w1',
        name: 'WebDAV',
        host: '192.168.1.*',
        basePath: const [''],
        port: '80',
        username: 'u',
        password: 'p',
        https: false,
        resolvedHosts: resolvedHosts,
      ) as WebDAVStorage;

  FileItem item(String name) => FileItem(
        storageId: 'w1',
        storageType: StorageType.webdav,
        name: name,
        uri: name,
        path: [name],
      );

  test('local storage is returned as-is without any listing', () async {
    final storage = local();
    var listed = false;
    final result = await prepareStorageForScan(
      storage,
      list: (s, p) async {
        listed = true;
        return FileListResult.empty;
      },
    );
    expect(result.ok, isTrue);
    expect(identical(result.storage, storage), isTrue);
    expect(listed, isFalse);
  });

  test('remote listing failure is classified, scan is not started', () async {
    final result = await prepareStorageForScan(
      ftp(),
      list: (s, p) async => const FileListResult(
        <FileItem>[],
        errorKind: StorageListErrorKind.unreachable,
        errorDetail: 'connection refused',
      ),
    );
    expect(result.ok, isFalse);
    expect(result.errorKind, StorageListErrorKind.unreachable);
    expect(result.errorDetail, 'connection refused');
  });

  test('remote listing success starts the scan', () async {
    final result = await prepareStorageForScan(
      ftp(),
      list: (s, p) async => FileListResult([item('a.mp4')]),
    );
    expect(result.ok, isTrue);
    expect(result.storage, isA<FTPStorage>());
  });

  test('wildcard resolve failure is classified', () async {
    final result = await prepareStorageForScan(
      wildcard(),
      resolve: (s, excluded) async => const WebDavResolveOutcome(
        errorKind: StorageListErrorKind.unreachable,
        errorDetail: 'no candidate host answered',
      ),
      readback: (_) => null,
      list: (s, p) async => FileListResult([item('a.mp4')]),
    );
    expect(result.ok, isFalse);
    expect(result.errorKind, StorageListErrorKind.unreachable);
  });

  test('wildcard resolve success scans the resolved entry', () async {
    final stored = wildcard(resolvedHosts: const ['192.168.1.5']);
    final result = await prepareStorageForScan(
      wildcard(),
      resolve: (s, excluded) async =>
          const WebDavResolveOutcome(host: '192.168.1.5'),
      readback: (_) => stored,
      list: (s, p) async => FileListResult([item('a.mp4')]),
    );
    expect(result.ok, isTrue);
    final target = result.storage! as WebDAVStorage;
    expect(target.resolvedHost, '192.168.1.5');
  });

  test('wildcard empty root re-resolves and treats still-empty as unreachable',
      () async {
    var resolveCalls = 0;
    final result = await prepareStorageForScan(
      wildcard(resolvedHosts: const ['192.168.1.5']),
      resolve: (s, excluded) async {
        resolveCalls++;
        // First resolve (no exclusions) picks a host; the retry excludes the
        // cached host and finds nothing new.
        if (excluded.isEmpty) {
          return const WebDavResolveOutcome(host: '192.168.1.5');
        }
        return const WebDavResolveOutcome(
          errorKind: StorageListErrorKind.unreachable,
          errorDetail: 'none',
        );
      },
      readback: (_) => wildcard(resolvedHosts: const ['192.168.1.5']),
      list: (s, p) async => FileListResult.empty,
    );
    expect(result.ok, isFalse);
    expect(result.errorKind, StorageListErrorKind.unreachable);
    expect(resolveCalls, 2);
  });
}
