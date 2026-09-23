import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iris/store/kv/kv_store.dart';

/// [KvStore] adapter over `flutter_secure_storage`.
///
/// Single place that knows the plugin options: Android uses encrypted
/// shared preferences (matching the historical call sites); other platforms
/// use the plugin defaults.
class SecureStorageKv implements KvStore {
  SecureStorageKv({FlutterSecureStorage? storage})
      : _storage = storage ??
            FlutterSecureStorage(
              aOptions: const AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);

  @override
  Future<bool> containsKey({required String key}) =>
      _storage.containsKey(key: key);

  @override
  Future<Map<String, String>> readAll() => _storage.readAll();
}

/// Test-only in-memory backend (also handy for golden/widget tests).
class MemoryKvStore implements KvStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
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
