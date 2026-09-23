import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/db/security/storage_cipher.dart';

/// Controllable stand-in for the platform secure storage.
class _FakeSecureStorage extends FlutterSecureStorage {
  _FakeSecureStorage({
    this.readDelay = Duration.zero,
    Map<String, String> seed = const <String, String>{},
  }) : backing = Map<String, String>.of(seed);

  final Duration readDelay;
  final Map<String, String> backing;
  final List<String> writtenKeys = <String>[];

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (readDelay > Duration.zero) await Future.delayed(readDelay);
    return backing[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    writtenKeys.add(key);
    if (value == null) {
      backing.remove(key);
    } else {
      backing[key] = value;
    }
  }
}

void main() {
  setUp(() {
    StorageCipher.resetForTest();
    StorageCipher.keyReadTimeout = const Duration(milliseconds: 50);
  });

  tearDown(() {
    StorageCipher.keyReadTimeout = const Duration(seconds: 5);
    StorageCipher.resetForTest();
  });

  test('slow read must not trigger key generation + overwrite', () async {
    // A timed-out read is NOT proof of absence: the real key may still be
    // sitting in secure storage. Generating a new key and persisting it
    // would permanently strand every previously encrypted password.
    final fake =
        _FakeSecureStorage(readDelay: const Duration(milliseconds: 500));
    await StorageCipher.encrypt('p@ssw0rd', storage: fake);
    expect(
      fake.writtenKeys,
      isEmpty,
      reason: 'must not overwrite the persisted key on a slow read',
    );
  });

  test('absent key is generated and persisted', () async {
    final fake = _FakeSecureStorage();
    final enc = await StorageCipher.encrypt('hello', storage: fake);
    expect(fake.writtenKeys, <String>['storage_encryption_key']);
    final plain =
        await StorageCipher.decrypt(enc.cipher, enc.nonce, storage: fake);
    expect(plain, 'hello');
  });

  test('existing key is reused, never regenerated', () async {
    final fake = _FakeSecureStorage();
    await StorageCipher.encrypt('first', storage: fake);
    final writesAfterFirst = fake.writtenKeys.length;
    final enc = await StorageCipher.encrypt('second', storage: fake);
    expect(fake.writtenKeys.length, writesAfterFirst);
    expect(
      await StorageCipher.decrypt(enc.cipher, enc.nonce, storage: fake),
      'second',
    );
  });

  test('slow read still decrypts data written with the real key', () async {
    // The persisted key arrives late (slow cold start). The timeout path
    // must not destroy it: once the read completes, the real key wins.
    final fake = _FakeSecureStorage();
    final enc = await StorageCipher.encrypt('s3cret', storage: fake);
    expect(fake.writtenKeys, hasLength(1));

    StorageCipher.resetForTest();
    final slowFake = _FakeSecureStorage(
      seed: Map<String, String>.of(fake.backing),
      readDelay: const Duration(milliseconds: 500),
    );
    // Trigger (and ride out) the timeout path.
    await StorageCipher.encrypt('ephemeral-noise', storage: slowFake);
    expect(slowFake.writtenKeys, isEmpty);

    // The persisted key is untouched: decrypting the ORIGINAL ciphertext
    // with the stored key still works.
    StorageCipher.resetForTest();
    final fastFake =
        _FakeSecureStorage(seed: Map<String, String>.of(slowFake.backing));
    expect(
      await StorageCipher.decrypt(enc.cipher, enc.nonce, storage: fastFake),
      's3cret',
    );
  });
}
