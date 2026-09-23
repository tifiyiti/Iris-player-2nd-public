import 'package:flutter_test/flutter_test.dart';
import 'package:iris/store/kv/kv_store.dart';
import 'package:iris/store/kv/use_kv_store.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_history_store.dart';

/// A backend failure during load (secure storage down, corrupt blob) must
/// NOT be reported as "loaded empty": the durability gate in
/// [PersistentStore] would otherwise let the next settings/history write
/// overwrite the user's real data with defaults.
class _SpyKv implements KvStore {
  _SpyKv({required this.throwOnRead, Map<String, String>? seed})
      : values = Map<String, String>.of(seed ?? const <String, String>{});

  final bool throwOnRead;
  final Map<String, String> values;
  int writes = 0;

  @override
  Future<String?> read({required String key}) async {
    if (throwOnRead) throw StateError('backend down');
    return values[key];
  }

  @override
  Future<void> write({required String key, required String value}) async {
    writes++;
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }

  @override
  Future<bool> containsKey({required String key}) async =>
      values.containsKey(key);

  @override
  Future<Map<String, String>> readAll() async => Map.of(values);
}

void main() {
  setUp(() {
    resetKvStoreForTest();
  });

  tearDown(() {
    resetKvStoreForTest();
  });

  test('HistoryStore load failure keeps loadOk false', () async {
    setKvStoreForTest(_SpyKv(throwOnRead: true));
    final store = HistoryStore();
    await store.initialized;
    expect(store.loadOk, isFalse);
    await store.dispose();
  });

  test('AppStore load failure keeps loadOk false', () async {
    setKvStoreForTest(_SpyKv(throwOnRead: true));
    final store = AppStore();
    await store.initialized;
    expect(store.loadOk, isFalse);
    await store.dispose();
  });

  test('HistoryStore.save is skipped when load failed', () async {
    final kv = _SpyKv(throwOnRead: true);
    setKvStoreForTest(kv);
    final store = HistoryStore();
    await store.initialized;
    expect(store.loadOk, isFalse);

    await store.save(store.state);
    expect(kv.writes, 0,
        reason: 'a never-loaded store must not persist defaults');

    await store.dispose();
    expect(kv.writes, 0);
  });

  test('AppStore.save is skipped when load failed', () async {
    final kv = _SpyKv(throwOnRead: true);
    setKvStoreForTest(kv);
    final store = AppStore();
    await store.initialized;
    expect(store.loadOk, isFalse);

    await store.save(store.state);
    expect(kv.writes, 0,
        reason: 'a never-loaded store must not persist defaults');

    await store.dispose();
    expect(kv.writes, 0);
  });

  test('save proceeds normally once load succeeded', () async {
    final kv = _SpyKv(throwOnRead: false);
    setKvStoreForTest(kv);

    final history = HistoryStore();
    await history.initialized;
    expect(history.loadOk, isTrue);
    await history.save(history.state);
    expect(kv.writes, 1);

    final app = AppStore();
    await app.initialized;
    expect(app.loadOk, isTrue);
    await app.save(app.state);
    expect(kv.writes, 2);

    // Cleanup only: dispose saves again (loaded stores persist on exit).
    await history.dispose();
    await app.dispose();
  });
}
