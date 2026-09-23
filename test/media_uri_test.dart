import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/services/media_uri.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/utils/path_conv.dart';

WebDAVStorage _webdav({
  String host = '192.168.*.*',
  List<String> resolvedHosts = const <String>[],
  String port = '8090',
  bool https = false,
  List<String> basePath = const <String>['/'],
}) =>
    WebDAVStorage(
      id: 's1',
      name: 'nas',
      host: host,
      resolvedHosts: resolvedHosts,
      basePath: basePath,
      port: port,
      username: 'u',
      password: 'p',
      https: https,
    );

FTPStorage _ftp({String host = '192.168.1.9', String port = '21'}) => FTPStorage(
      id: 'f1',
      name: 'ftp',
      host: host,
      basePath: const <String>['/'],
      port: port,
      username: 'u',
      password: 'p',
    );

/// The DB keeps the storage-relative path as the identity and the remote address
/// is DERIVED from the storage record, so a wildcard entry tracks its current
/// resolution instead of baking a host into `media_nodes`.
void main() {
  group('webdavPlayableUri', () {
    test('uses the resolved host for a wildcard entry', () {
      expect(
        webdavPlayableUri(
            _webdav(resolvedHosts: const <String>['192.168.1.4']),
            const <String>['a.mp4']),
        'http://192.168.1.4:8090/a.mp4',
      );
    });

    test('falls back to the configured host when nothing is resolved', () {
      expect(
        webdavPlayableUri(_webdav(host: 'nas.local'), const <String>['a.mp4']),
        'http://nas.local:8090/a.mp4',
      );
    });

    test('honours https and a non-default port', () {
      expect(
        webdavPlayableUri(
            _webdav(
                https: true,
                port: '8443',
                resolvedHosts: const <String>['192.168.1.4']),
            const <String>['a.mp4']),
        'https://192.168.1.4:8443/a.mp4',
      );
    });

    test('keeps nested segments and a non-root base path', () {
      expect(
        webdavPlayableUri(
            _webdav(
                basePath: const <String>['/dav'],
                resolvedHosts: const <String>['192.168.1.4']),
            const <String>['dav', 'anime', 'b.mp4']),
        'http://192.168.1.4:8090/dav/anime/b.mp4',
      );
    });

    test('tolerates a legacy slash-prefixed node path', () {
      expect(
        webdavPlayableUri(
            _webdav(resolvedHosts: const <String>['192.168.1.4']),
            const <String>['/', 'a.mp4']),
        'http://192.168.1.4:8090/a.mp4',
      );
    });
  });

  group('ftpPlayableUri', () {
    test('builds the relative form the player proxy-prefixes', () {
      expect(
        ftpPlayableUri(_ftp(), const <String>['anime', 'b.mp4']),
        'ftp?host=192.168.1.9&port=21&path=/anime/b.mp4',
      );
    });

    test('keeps the leading slash the listing producer uses', () {
      expect(
        ftpPlayableUri(_ftp(), const <String>['a.mp4']),
        'ftp?host=192.168.1.9&port=21&path=/a.mp4',
      );
    });

    test('mediaNodePlayableUri derives it for FTP rows', () {
      expect(
        mediaNodePlayableUri(_ftp(), const <String>['anime', 'b.mp4']),
        'ftp?host=192.168.1.9&port=21&path=/anime/b.mp4',
      );
    });
  });

  group('mediaNodePlayableUri', () {
    test('prefers a persisted SAF uri', () {
      expect(
        mediaNodePlayableUri(
          _webdav(resolvedHosts: const <String>['192.168.1.4']),
          const <String>['a.mp4'],
          uri: 'content://tree/a.mp4',
        ),
        'content://tree/a.mp4',
      );
    });

    test('derives the WebDAV address from the storage record', () {
      expect(
        mediaNodePlayableUri(
          _webdav(resolvedHosts: const <String>['192.168.1.4']),
          const <String>['anime', 'b.mp4'],
        ),
        'http://192.168.1.4:8090/anime/b.mp4',
      );
    });

    test('local storages and unknown storages keep the path form', () {
      final local = Storage.local(
        id: 'l1',
        type: StorageType.sdcard,
        name: 'sd',
        basePath: const <String>['/sdcard'],
      );
      expect(
        mediaNodePlayableUri(local, const <String>['sdcard', 'x.mp4']),
        playableUri(const <String>['sdcard', 'x.mp4']),
      );
      expect(
        mediaNodePlayableUri(null, const <String>['a', 'x.mp4']),
        playableUri(const <String>['a', 'x.mp4']),
      );
    });
  });
}
