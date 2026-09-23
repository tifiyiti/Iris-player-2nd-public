import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

// File-level encryption for transfer envelopes.
// Uses AES-GCM 256 + PBKDF2-HMAC-SHA256. Pure Dart, cross-platform.
// Passphrase is user-supplied (numeric 4+ digits or arbitrary).
// The file is never plaintext when network storages are included.

class TransferCrypto {
  static const String kCipher = 'AESGCM';
  static const String kKdf = 'PBKDF2SHA256';
  static const int kIterations = 100000;
  static const int kSaltLen = 16;
  static const int kNonceLen = 12;

  static final AesGcm _aes = AesGcm.with256bits();
  static final Pbkdf2 _pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: kIterations,
    bits: 256,
  );

  static Uint8List _randomBytes(int len) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(len, (_) => r.nextInt(256)));
  }

  static Future<SecretKey> _deriveKey(String passphrase, Uint8List salt) async {
    return _pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
  }

  // Encrypts [plaintextJson] (a JSON string) with [passphrase].
  // Returns enc map to embed in envelope.
  static Future<Map<String, dynamic>> encrypt({
    required String plaintextJson,
    required String passphrase,
    required String kind, // numeric | custom
  }) async {
    final salt = _randomBytes(kSaltLen);
    final nonce = _randomBytes(kNonceLen);
    final key = await _deriveKey(passphrase, salt);
    final secretBox = await _aes.encrypt(
      utf8.encode(plaintextJson),
      secretKey: key,
      nonce: nonce,
    );
    return {
      'kind': kind,
      'cipher': kCipher,
      'kdf': kKdf,
      'iterations': kIterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(secretBox.nonce),
      'data': base64Encode(secretBox.cipherText + secretBox.mac.bytes),
    };
  }

  // Decrypts enc map with [passphrase], returns plaintext JSON string.
  static Future<String> decrypt({
    required Map<String, dynamic> enc,
    required String passphrase,
  }) async {
    final salt = base64Decode(enc['salt'] as String);
    final nonce = base64Decode(enc['nonce'] as String);
    final data = base64Decode(enc['data'] as String);
    // cryptography stores mac as 16 bytes appended; we stored cipherText+mac
    // Need to split. AES-GCM mac is 16 bytes.
    if (data.length < 16) throw Exception('Invalid encrypted data');
    final cipherText = data.sublist(0, data.length - 16);
    final macBytes = data.sublist(data.length - 16);
    final key = await _deriveKey(passphrase, Uint8List.fromList(salt));
    final secretBox = SecretBox(
      cipherText,
      nonce: nonce,
      mac: Mac(macBytes),
    );
    final plain = await _aes.decrypt(secretBox, secretKey: key);
    return utf8.decode(plain);
  }

  static bool isEncryptedEnvelope(Map<String, dynamic> json) => json.containsKey('enc');
}
