import 'package:iris/store/kv/kv_store.dart';

/// Per-key routing [KvStore]: credential-bearing keys always hit the
/// machine-bound encrypted backend, everything else goes to the portable
/// file backend so it travels with the folder.
class RoutedKv implements KvStore {
  RoutedKv({
    required KvStore fileKv,
    required KvStore secureKv,
    Set<String> secretKeys = const {},
  })  : _fileKv = fileKv,
        _secureKv = secureKv,
        _secretKeys = Set.unmodifiable(secretKeys);

  final KvStore _fileKv;
  final KvStore _secureKv;
  final Set<String> _secretKeys;

  KvStore _backendFor(String key) =>
      _secretKeys.contains(key) ? _secureKv : _fileKv;

  @override
  Future<String?> read({required String key}) => _backendFor(key).read(key: key);

  @override
  Future<void> write({required String key, required String value}) =>
      _backendFor(key).write(key: key, value: value);

  @override
  Future<void> delete({required String key}) =>
      _backendFor(key).delete(key: key);

  @override
  Future<bool> containsKey({required String key}) =>
      _backendFor(key).containsKey(key: key);

  @override
  Future<Map<String, String>> readAll() async {
    // Secure side wins on collisions: secret values must never be shadowed
    // by a stale portable copy (e.g. after an import from an old install).
    return {
      ...await _fileKv.readAll(),
      ...await _secureKv.readAll(),
    };
  }
}
