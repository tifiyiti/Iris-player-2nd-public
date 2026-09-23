import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/webdav_discovery/services/webdav_group.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/models/storages/storage_scope_key.dart';

WebDAVStorage _webdav({
  required String id,
  String host = '192.168.1.5',
  String port = '5005',
  String username = 'alice',
  bool https = false,
  List<String> basePath = const <String>['/'],
  List<String> resolvedHosts = const <String>[],
  String? dataScopeId,
}) =>
    WebDAVStorage(
      id: id,
      name: id,
      host: host,
      resolvedHosts: resolvedHosts,
      basePath: basePath,
      port: port,
      username: username,
      password: 'p',
      https: https,
      dataScopeId: dataScopeId,
    );

FTPStorage _ftp({
  required String id,
  String host = '10.0.0.2',
  String port = '21',
  String username = 'bob',
  List<String> basePath = const <String>['/'],
  String? dataScopeId,
}) =>
    FTPStorage(
      id: id,
      name: id,
      host: host,
      basePath: basePath,
      port: port,
      username: username,
      password: 'p',
      dataScopeId: dataScopeId,
    );

void main() {
  group('findSharedScope account matching', () {
    test('same account + same path tree matches', () {
      final match = findSharedScope(
        _webdav(id: 'b'),
        [_webdav(id: 'a')],
      );
      expect(match, isNotNull);
      expect(match!.scopeId, 'a');
    });

    test('wildcard and concrete host overlap without network', () {
      final match = findSharedScope(
        _webdav(id: 'b', host: '192.168.*.*'),
        [_webdav(id: 'a', host: '192.168.1.5')],
      );
      expect(match, isNotNull);
    });

    test('resolved hosts participate in overlap', () {
      final match = findSharedScope(
        _webdav(id: 'b', host: '192.168.*.*', resolvedHosts: ['192.168.1.9']),
        [_webdav(id: 'a', host: '10.0.0.1', resolvedHosts: ['192.168.1.9'])],
      );
      expect(match, isNotNull);
    });

    test('different username, port, or https never match', () {
      expect(
        findSharedScope(_webdav(id: 'b', username: 'x'), [_webdav(id: 'a')]),
        isNull,
      );
      expect(
        findSharedScope(_webdav(id: 'b', port: '80'), [_webdav(id: 'a')]),
        isNull,
      );
      expect(
        findSharedScope(_webdav(id: 'b', https: true), [_webdav(id: 'a')]),
        isNull,
      );
    });

    test('FTP matches on host/port/username', () {
      expect(findSharedScope(_ftp(id: 'b'), [_ftp(id: 'a')]), isNotNull);
      expect(
        findSharedScope(_ftp(id: 'b', port: '2121'), [_ftp(id: 'a')]),
        isNull,
      );
    });

    test('a local storage never shares', () {
      final local = LocalStorage(
        id: 'l',
        type: StorageType.internal,
        name: 'l',
        basePath: const <String>['/'],
      );
      expect(findSharedScope(local, [_webdav(id: 'a')]), isNull);
      expect(findSharedScope(_webdav(id: 'b'), [local]), isNull);
    });
  });

  group('findSharedScope path-tree relation', () {
    test('equal paths match', () {
      expect(
        findSharedScope(
          _webdav(id: 'b', basePath: const ['media']),
          [_webdav(id: 'a', basePath: const ['media'])],
        ),
        isNotNull,
      );
    });

    test('containment either direction matches', () {
      expect(
        findSharedScope(
          _webdav(id: 'b', basePath: const ['/']),
          [_webdav(id: 'a', basePath: const ['media/movies'])],
        ),
        isNotNull,
      );
      expect(
        findSharedScope(
          _webdav(id: 'b', basePath: const ['media/movies']),
          [_webdav(id: 'a', basePath: const ['/'])],
        ),
        isNotNull,
      );
    });

    test('disjoint paths do not match even with the same account', () {
      expect(
        findSharedScope(
          _webdav(id: 'b', basePath: const ['movies']),
          [_webdav(id: 'a', basePath: const ['music'])],
        ),
        isNull,
      );
    });
  });

  group('findSharedScope scope resolution', () {
    test('uses the existing entry dataScopeId when linked, else its id', () {
      expect(
        findSharedScope(_webdav(id: 'b'), [_webdav(id: 'a')])!.scopeId,
        'a',
      );
      expect(
        findSharedScope(
          _webdav(id: 'b'),
          [_webdav(id: 'a', dataScopeId: 'owner')],
        )!.scopeId,
        'owner',
      );
    });

    test('never matches the same id', () {
      expect(findSharedScope(_webdav(id: 'a'), [_webdav(id: 'a')]), isNull);
    });
  });

  group('claimedBySiblings with data scope', () {
    test('independent same-account entries still claim each other', () {
      final a = _webdav(id: 'a', resolvedHosts: const ['192.168.1.5']);
      final b = _webdav(id: 'b');
      expect(claimedBySiblings(b, [a, b]), {'192.168.1.5'});
    });

    test('linked entries (same scope) never claim each other', () {
      final a = _webdav(id: 'a', resolvedHosts: const ['192.168.1.5']);
      final b = _webdav(id: 'b', dataScopeId: 'a');
      expect(claimedBySiblings(b, [a, b]), isEmpty);
      expect(claimedBySiblings(a, [a, b]), isEmpty);
    });
  });

  group('resolveStorageForNode', () {
    test('prefers the viewing entry when it shares the node scope', () {
      final a = _webdav(id: 'a');
      final b = _webdav(id: 'b', dataScopeId: 'a');
      final resolved = resolveStorageForNode(
        storages: [a, b],
        viewingId: 'b',
        nodeStorageId: 'a',
      );
      expect(resolved?.id, 'b');
    });

    test('falls back to the writer when no viewing entry', () {
      final a = _webdav(id: 'a');
      final b = _webdav(id: 'b', dataScopeId: 'a');
      expect(
        resolveStorageForNode(storages: [a, b], nodeStorageId: 'a')?.id,
        'a',
      );
    });

    test('falls back to a surviving scope member when the writer is gone', () {
      final survivor = _webdav(id: 'b', dataScopeId: 'a');
      expect(
        resolveStorageForNode(storages: [survivor], nodeStorageId: 'a')?.id,
        'b',
      );
    });

    test('ignores a viewing entry in a different scope', () {
      final other = _webdav(id: 'c');
      final writer = _webdav(id: 'a');
      expect(
        resolveStorageForNode(
          storages: [other, writer],
          viewingId: 'c',
          nodeStorageId: 'a',
        )?.id,
        'a',
      );
    });

    test('returns null when nothing shares the scope', () {
      final unrelated = _webdav(id: 'c');
      expect(
        resolveStorageForNode(storages: [unrelated], nodeStorageId: 'a'),
        isNull,
      );
    });
  });

  group('repairImportedScopes', () {
    test('clears a dangling scope id with no same-tree entry', () {
      final b = _webdav(id: 'b', dataScopeId: 'gone');
      final repaired = repairImportedScopes(merged: [b], imported: [b]);
      expect(repaired.single.dataScopeId, isNull);
    });

    test('re-links a dangling scope to a merged same-tree entry', () {
      final local = _webdav(id: 'a');
      final b = _webdav(id: 'b', dataScopeId: 'gone');
      final repaired =
          repairImportedScopes(merged: [local, b], imported: [b]);
      expect(repaired.last.dataScopeId, 'a');
    });

    test('keeps a scope whose target survives', () {
      final a = _webdav(id: 'a');
      final b = _webdav(id: 'b', dataScopeId: 'a');
      final repaired = repairImportedScopes(merged: [a, b], imported: [b]);
      expect(repaired.last.dataScopeId, 'a');
    });

    test('leaves locally-present entries untouched', () {
      final local = _webdav(id: 'a', dataScopeId: 'gone');
      final repaired = repairImportedScopes(merged: [local], imported: const []);
      expect(repaired.single.dataScopeId, 'gone');
    });
  });
}
