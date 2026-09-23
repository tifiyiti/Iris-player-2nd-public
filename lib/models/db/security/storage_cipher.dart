import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iris/utils/logger.dart';

/// Row-level encryption for WebDAV/FTP passwords stored in Drift.
///
/// - Key: 256-bit random, persisted in `flutter_secure_storage` under
///   `storage_encryption_key` (base64). Generated once, never leaves the
///   device (portable `userdata/db` stays encrypted at rest).
/// - Algorithm: AES-GCM 256 (pure Dart via `cryptography`, cross-platform).
/// - Stored columns: `password_cipher` = base64(cipherText+mac), `password_nonce` = base64(nonce).
/// - Plaintext column `password` is kept for migration only and cleared after
///   successful encryption; reads prefer cipher when present.
class StorageCipher {
  static const String _keyName = 'storage_encryption_key';
  static final AesGcm _aes = AesGcm.with256bits();
  static final AreaKeyLog _log = AreaKeyLog(LogKeys.legacyDb);

  static Uint8List _randomBytes(int len) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(len, (_) => r.nextInt(256)));
  }

  // In-memory fallback for `flutter test` (no platform channel) or when
  // secure storage throws. Keeps the process bootable; data is ephemeral
  // but tests remain deterministic.
  static Uint8List? _memoryKey;

  /// How long a key read may take before it is treated as "too slow to
  /// trust". Generous on purpose: a slow cold-start read must still return
  /// the REAL key instead of triggering a rotation.
  @visibleForTesting
  static Duration keyReadTimeout = const Duration(seconds: 5);

  /// Test seam: drop cached in-process key material between cases.
  @visibleForTesting
  static void resetForTest() {
    _memoryKey = null;
  }

  static Future<SecretKey> _getOrCreateKey({FlutterSecureStorage? storage}) async {
    // Reuse the in-process key when the caller doesn't supply a backend
    // (production path after a fallback). Deliberately does NOT cache an
    // in-flight future: a single hung platform read must not poison every
    // later call by sharing one never-completing Future.
    if (storage == null && _memoryKey != null) {
      return SecretKey(_memoryKey!);
    }
    return _resolveKey(storage: storage);
  }

  static Future<SecretKey> _resolveKey({FlutterSecureStorage? storage}) async {
    final s = storage ??
        const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
        );
    // A slow or unreachable read is NOT proof that no key exists. Treating
    // a timeout as absence, minting a fresh key and overwriting the stored
    // one permanently strands every previously encrypted password — so the
    // timeout/error paths degrade to an ephemeral in-process key and NEVER
    // write.
    String? b64;
    try {
      b64 = await s.read(key: _keyName).timeout(keyReadTimeout);
    } on TimeoutException {
      _log.e('StorageCipher: key read timed out; '
          'using ephemeral memory key, nothing persisted');
      _memoryKey ??= _randomBytes(32);
      return SecretKey(_memoryKey!);
    } catch (e) {
      _log.w('StorageCipher: secure storage unavailable, using memory key: $e');
      _memoryKey ??= _randomBytes(32);
      return SecretKey(_memoryKey!);
    }
    if (b64 != null && b64.isNotEmpty) {
      try {
        final bytes = base64Decode(b64);
        if (bytes.length == 32) return SecretKey(bytes);
      } catch (_) {}
      _log.w('StorageCipher: stored key invalid, regenerating');
    }
    // Definitive absence (or a corrupt value): generate once and persist.
    final keyBytes = _randomBytes(32);
    try {
      await s
          .write(key: _keyName, value: base64Encode(keyBytes))
          .timeout(keyReadTimeout);
    } on TimeoutException {
      _log.e('StorageCipher: key write timed out; '
          'generated key kept in memory only');
    } catch (e) {
      _log.e('StorageCipher: key write failed; '
          'generated key kept in memory only: $e');
    }
    _memoryKey = keyBytes;
    _log.i('StorageCipher: generated new 256-bit key');
    return SecretKey(keyBytes);
  }

  /// Encrypts [plaintext] with the device key.
  /// Returns (cipher=base64(cipherText+mac), nonce=base64(nonce)).
  static Future<({String cipher, String nonce})> encrypt(
    String plaintext, {
    FlutterSecureStorage? storage,
  }) async {
    final key = await _getOrCreateKey(storage: storage);
    final nonce = _randomBytes(12);
    final box = await _aes.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: nonce,
    );
    final cipherAndMac = Uint8List.fromList([...box.cipherText, ...box.mac.bytes]);
    return (
      cipher: base64Encode(cipherAndMac),
      nonce: base64Encode(box.nonce),
    );
  }

  /// Decrypts a (cipher, nonce) pair produced by [encrypt].
  static Future<String> decrypt(
    String cipher,
    String nonce, {
    FlutterSecureStorage? storage,
  }) async {
    final key = await _getOrCreateKey(storage: storage);
    final cipherAndMac = base64Decode(cipher);
    final nonceBytes = base64Decode(nonce);
    if (cipherAndMac.length < 16) throw Exception('Invalid cipher length');
    final cipherText = cipherAndMac.sublist(0, cipherAndMac.length - 16);
    final macBytes = cipherAndMac.sublist(cipherAndMac.length - 16);
    final box = SecretBox(
      cipherText,
      nonce: nonceBytes,
      mac: Mac(macBytes),
    );
    final plain = await _aes.decrypt(box, secretKey: key);
    return utf8.decode(plain);
  }

  /// Test helper: wipe the stored key (forces regeneration on next use).
  static Future<void> clearKey({FlutterSecureStorage? storage}) async {
    final s = storage ??
        const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
        );
    await s.delete(key: _keyName);
  }
}
