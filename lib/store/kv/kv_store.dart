/// Minimal key-value contract shared by every persistence backend used by
/// `PersistentStore` implementations.
///
/// The facade exists so stores never depend on a concrete storage plugin:
/// installed mode binds to encrypted secure storage, portable Windows mode
/// routes non-secret keys to a JSON file inside the movable `userdata` root
/// (see [RoutedKv]).
abstract interface class KvStore {
  /// Named-parameter shape mirrors the historical flutter_secure_storage
  /// call sites so migrations stay one-line swaps.
  Future<String?> read({required String key});

  Future<void> write({required String key, required String value});

  Future<void> delete({required String key});

  Future<bool> containsKey({required String key});

  /// All entries visible to this backend (both backends merged by the
  /// caller when routing).
  Future<Map<String, String>> readAll();
}
