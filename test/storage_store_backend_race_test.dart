import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/store/storage_state.dart';
import 'package:iris/store/db/storage_persistence.dart';
import 'package:iris/store/use_storage_store.dart';

/// A backend switch that lands while the initial load is still in flight
/// must win: the stale in-flight snapshot must not overwrite the switched
/// backend's state afterwards (which would display one backend's data while
/// writing to the other).
class _ImmediatePersistence implements StoragePersistence {
  _ImmediatePersistence(this.stateToReturn);

  final StorageState? stateToReturn;

  @override
  Future<StorageState?> load() async => stateToReturn;

  @override
  Future<void> save(StorageState state) async {}
}

class _GatedDbPersistence implements StoragePersistence {
  _GatedDbPersistence(this.stateToReturn, this.release);

  final StorageState? stateToReturn;
  final Completer<void> release;

  @override
  Future<StorageState?> load() async {
    await release.future;
    return stateToReturn;
  }

  @override
  Future<void> save(StorageState state) async {}
}

void main() {
  test('switchBackend during initial load wins over the stale snapshot',
      () async {
    final release = Completer<void>();
    final store = UnifiedStorageStore(
      legacyPersistence: _ImmediatePersistence(
        StorageState(currentPath: const ['legacy-marker']),
      ),
      dbPersistence: _GatedDbPersistence(
        StorageState(currentPath: const ['db-marker']),
        release,
      ),
    );
    // The constructor-started load is now parked inside the slow DB read.
    await store.switchBackend(true);
    expect(store.isUsingLegacy, isTrue);
    expect(store.state.currentPath, const ['legacy-marker']);

    // The stale DB snapshot lands afterwards: it must be discarded.
    release.complete();
    await store.initialized;
    expect(store.isUsingLegacy, isTrue);
    expect(
      store.state.currentPath,
      const ['legacy-marker'],
      reason: 'stale in-flight DB snapshot must not clobber the '
          'switched backend state',
    );
    await store.dispose();
  });
}
