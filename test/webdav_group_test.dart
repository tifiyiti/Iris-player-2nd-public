import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/webdav_discovery/services/webdav_group.dart';
import 'package:iris/models/storages/storage.dart';

WebDAVStorage webdav({
  required String id,
  String host = '192.168.1.*',
  String port = '5005',
  String username = 'alice',
  bool https = false,
  List<String> resolvedHosts = const <String>[],
}) =>
    WebDAVStorage(
      id: id,
      name: id,
      host: host,
      resolvedHosts: resolvedHosts,
      basePath: const <String>['/'],
      port: port,
      username: username,
      password: 'p',
      https: https,
    );

void main() {
  group('webdavGroupKey', () {
    test('groups by pattern + endpoint + account', () {
      expect(webdavGroupKey(webdav(id: 'a')), webdavGroupKey(webdav(id: 'b')));
    });

    test('different account/port/scheme/pattern are different groups', () {
      final base = webdav(id: 'a');
      expect(webdavGroupKey(webdav(id: 'b', username: 'bob')),
          isNot(webdavGroupKey(base)));
      expect(webdavGroupKey(webdav(id: 'b', port: '5006')),
          isNot(webdavGroupKey(base)));
      expect(webdavGroupKey(webdav(id: 'b', https: true)),
          isNot(webdavGroupKey(base)));
      expect(webdavGroupKey(webdav(id: 'b', host: '192.168.2.*')),
          isNot(webdavGroupKey(base)));
    });
  });

  group('claimedBySiblings', () {
    test('claims a same-group sibling active host', () {
      final me = webdav(id: 'a');
      final sibling = webdav(id: 'b', resolvedHosts: const <String>['192.168.1.5']);
      expect(claimedBySiblings(me, [me, sibling]), {'192.168.1.5'});
    });

    test('never claims its own host', () {
      final me = webdav(id: 'a', resolvedHosts: const <String>['192.168.1.5']);
      expect(claimedBySiblings(me, [me]), isEmpty);
    });

    test('ignores siblings in a different group', () {
      final me = webdav(id: 'a');
      final other =
          webdav(id: 'b', username: 'bob', resolvedHosts: const <String>['192.168.1.5']);
      expect(claimedBySiblings(me, [me, other]), isEmpty);
    });

    test('an unresolved sibling claims nothing', () {
      final me = webdav(id: 'a');
      final sibling = webdav(id: 'b');
      expect(claimedBySiblings(me, [me, sibling]), isEmpty);
    });
  });
}
