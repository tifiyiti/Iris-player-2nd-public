import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/services/media_uri.dart';
import 'package:iris/features/webdav_discovery/model/discovery_models.dart';
import 'package:iris/features/webdav_discovery/services/webdav_connect_coordinator.dart';
import 'package:iris/features/webdav_discovery/services/webdav_discovery.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/enums/storage_list_error.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/store/use_storage_store.dart';

import 'helpers/sqlite3_loader.dart';

/// Scripted resolver: emits exactly the given events, no network involved.
class _ScriptedDiscovery extends WebDavDiscovery {
  _ScriptedDiscovery(this.events);

  final List<DiscoveryEvent> events;

  @override
  Stream<DiscoveryEvent> resolve(
    WebDAVStorage storage, {
    Set<String> excludedHosts = const <String>{},
  }) =>
      Stream<DiscoveryEvent>.fromIterable(events);
}

WebDAVStorage _storage({String host = '192.168.*.*', List<String> resolved = const <String>[]}) =>
    WebDAVStorage(
      id: 's1',
      name: 'nas',
      host: host,
      resolvedHosts: resolved,
      basePath: const <String>['/'],
      port: '8090',
      username: 'u',
      password: 'p',
      https: false,
    );

void main() {
  ensureSqlite3Loaded();

  setUpAll(() async {
    await DbModule.init(AppDatabase(NativeDatabase.memory()));
    useStorageStore();
    await useStorageStore().initialized;
  });

  group('webdavNeedsResolution', () {
    test('true only for an unresolved wildcard', () {
      expect(webdavNeedsResolution(_storage()), isTrue);
      expect(
        webdavNeedsResolution(_storage(resolved: const <String>['192.168.1.4'])),
        isFalse,
      );
      expect(webdavNeedsResolution(_storage(host: '192.168.1.4')), isFalse);
    });
  });

  group('resolveDetailed outcomes', () {
    test('verified reports the host and no failure', () async {
      final coordinator = WebDavConnectCoordinator(
        discovery: _ScriptedDiscovery(const [DiscoveryVerified('192.168.1.4')]),
      );
      final outcome = await coordinator.resolveDetailed(_storage());

      expect(outcome.ok, isTrue);
      expect(outcome.host, '192.168.1.4');
      expect(outcome.errorKind, isNull);
    });

    test('exhausted reports an unreachable failure with detail', () async {
      final coordinator = WebDavConnectCoordinator(
        discovery: _ScriptedDiscovery(const [DiscoveryExhausted()]),
      );
      final outcome = await coordinator.resolveDetailed(_storage());

      expect(outcome.ok, isFalse);
      expect(outcome.host, isNull);
      expect(outcome.errorKind, StorageListErrorKind.unreachable);
      expect(outcome.errorDetail, isNotNull);
    });

    test('rejected credentials report unauthorized', () async {
      final coordinator = WebDavConnectCoordinator(
        discovery:
            _ScriptedDiscovery(const [DiscoveryAuthRejected('192.168.1.9')]),
      );
      final outcome = await coordinator.resolveDetailed(_storage());

      expect(outcome.errorKind, StorageListErrorKind.unauthorized);
      expect(outcome.errorDetail, contains('192.168.1.9'));
    });
  });
}
