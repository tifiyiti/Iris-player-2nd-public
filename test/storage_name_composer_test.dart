import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/storages/storage_name_composer.dart';
import 'package:iris/models/storages/storage_name_prefs.dart';

void main() {
  group('composeStorageName', () {
    test('respects the lit order, not the enum order', () {
      final name = composeStorageName(
        tags: const [StorageNameTag.host, StorageNameTag.type, StorageNameTag.account],
        separator: '·',
        typeLabel: 'WebDAV',
        username: 'alice',
        host: 'nas.local',
        port: '5005',
        isDefaultPort: false,
        pathLast: '',
      );
      expect(name, 'nas.local·WebDAV·alice');
    });

    test('omits empty components', () {
      final name = composeStorageName(
        tags: const [StorageNameTag.type, StorageNameTag.account, StorageNameTag.host],
        separator: ' - ',
        typeLabel: 'FTP',
        username: '',
        host: '10.0.0.2',
        port: '21',
        isDefaultPort: true,
        pathLast: '',
      );
      expect(name, 'FTP - 10.0.0.2');
    });

    test('omits the port when it is the default', () {
      final name = composeStorageName(
        tags: const [StorageNameTag.host, StorageNameTag.port],
        separator: ':',
        typeLabel: 'WebDAV',
        username: '',
        host: 'nas.local',
        port: '443',
        isDefaultPort: true,
        pathLast: '',
      );
      expect(name, 'nas.local');
    });

    test('includes the port when it is non-default', () {
      final name = composeStorageName(
        tags: const [StorageNameTag.host, StorageNameTag.port],
        separator: ':',
        typeLabel: 'WebDAV',
        username: '',
        host: 'nas.local',
        port: '5005',
        isDefaultPort: false,
        pathLast: '',
      );
      expect(name, 'nas.local:5005');
    });

    test('falls back to host when every component is empty', () {
      final name = composeStorageName(
        tags: const [StorageNameTag.type, StorageNameTag.account],
        separator: '·',
        typeLabel: '',
        username: '',
        host: 'nas.local',
        port: '',
        isDefaultPort: true,
        pathLast: '',
      );
      expect(name, 'nas.local');
    });

    test('supports an empty separator', () {
      final name = composeStorageName(
        tags: const [StorageNameTag.type, StorageNameTag.account],
        separator: '',
        typeLabel: 'FTP',
        username: 'bob',
        host: '',
        port: '21',
        isDefaultPort: true,
        pathLast: '',
      );
      expect(name, 'FTPbob');
    });
  });

  group('storageNameLastPathSegment', () {
    test('takes the last non-empty segment', () {
      expect(storageNameLastPathSegment(['/media/movies/']), 'movies');
    });

    test('ignores a root-only path', () {
      expect(storageNameLastPathSegment(['/']), '');
    });

    test('walks multiple entries backwards', () {
      expect(storageNameLastPathSegment(['/a/b', '/c']), 'c');
    });
  });

  group('default port detection', () {
    test('WebDAV http default is 80, empty counts as default', () {
      expect(isDefaultWebDavPort('', false), isTrue);
      expect(isDefaultWebDavPort('80', false), isTrue);
      expect(isDefaultWebDavPort('8080', false), isFalse);
    });

    test('WebDAV https default is 443', () {
      expect(isDefaultWebDavPort('', true), isTrue);
      expect(isDefaultWebDavPort('443', true), isTrue);
      expect(isDefaultWebDavPort('443', false), isFalse);
    });

    test('FTP default is 21', () {
      expect(isDefaultFtpPort(''), isTrue);
      expect(isDefaultFtpPort('21'), isTrue);
      expect(isDefaultFtpPort('2121'), isFalse);
    });
  });

  group('uniqueStorageName', () {
    test('returns the base when free', () {
      expect(uniqueStorageName('nas', const []), 'nas');
    });

    test('appends (2), (3)… on collision', () {
      final existing = <StorageNameEntry>[
        (id: 'a', name: 'nas'),
        (id: 'b', name: 'nas (2)'),
      ];
      expect(uniqueStorageName('nas', existing), 'nas (3)');
    });

    test('ignores the edited entry via excludeId', () {
      final existing = <StorageNameEntry>[(id: 'a', name: 'nas')];
      expect(uniqueStorageName('nas', existing, excludeId: 'a'), 'nas');
    });

    test('blank base stays blank', () {
      expect(uniqueStorageName('   ', const []), '');
    });
  });
}
