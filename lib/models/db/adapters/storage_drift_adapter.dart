import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/security/storage_cipher.dart';
import 'package:iris/models/storages/storage.dart';

extension StorageDriftAdapter on Storage {
  static Storage fromDb(StoragesTableData row) {
    return fromDbWithPassword(row, null);
  }

  /// Decodes the v29 JSON host list, falling back to the legacy single-value
  /// column so pre-v29 rows keep their cached host.
  static List<String> decodeResolvedHosts(String? encoded, String? legacy) {
    if (encoded != null && encoded.isNotEmpty) {
      try {
        final decoded = json.decode(encoded);
        if (decoded is List) {
          final out = <String>[];
          for (final e in decoded) {
            if (e is String && e.isNotEmpty) out.add(e);
          }
          if (out.isNotEmpty) return out;
        }
      } catch (_) {
        // Corrupt payload: fall through to the legacy column.
      }
    }
    if (legacy == null || legacy.isEmpty) return const <String>[];
    return <String>[legacy];
  }

  /// Synchronous fallback that uses [decryptedPassword] when supplied,
  /// otherwise prefers row.passwordCipher (if present it is treated as opaque
  /// and returned as-is — callers that need plaintext should use [fromDbAsync]).
  static Storage fromDbWithPassword(
      StoragesTableData row, String? decryptedPassword) {
    final basePath = List<String>.from(json.decode(row.basePath));
    StorageType type;
    if (row.type < 0 || row.type >= StorageType.values.length) {
      type = StorageType.none;
    } else {
      type = StorageType.values[row.type];
    }

    // Prefer decrypted cipher password, then legacy plaintext.
    String? effectivePassword = decryptedPassword ?? row.password;

    switch (type) {
      case StorageType.webdav:
        if (row.host == null ||
            row.port == null ||
            row.username == null ||
            effectivePassword == null) {
          return Storage.local(
            id: row.id,
            type: StorageType.none,
            name: row.name,
            basePath: basePath,
            dataScopeId: row.dataScopeId,
            volumeId: row.volumeId,
          );
        }
        return Storage.webdav(
          id: row.id,
          name: row.name,
          host: row.host!,
          resolvedHosts: decodeResolvedHosts(row.resolvedHosts, row.resolvedHost),
          basePath: basePath,
          port: row.port!,
          username: row.username!,
          password: effectivePassword,
          https: row.https ?? false,
          dataScopeId: row.dataScopeId,
        );

      case StorageType.ftp:
        if (row.host == null ||
            row.port == null ||
            row.username == null ||
            effectivePassword == null) {
          return Storage.local(
            id: row.id,
            type: StorageType.none,
            name: row.name,
            basePath: basePath,
            dataScopeId: row.dataScopeId,
            volumeId: row.volumeId,
          );
        }
        return Storage.ftp(
          id: row.id,
          name: row.name,
          host: row.host!,
          basePath: basePath,
          port: row.port!,
          username: row.username!,
          password: effectivePassword,
          dataScopeId: row.dataScopeId,
        );

      default:
        return Storage.local(
          id: row.id,
          type: type,
          name: row.name,
          basePath: basePath,
          dataScopeId: row.dataScopeId,
          volumeId: row.volumeId,
        );
    }
  }

  /// Async variant that decrypts row-level cipher when present.
  static Future<Storage> fromDbAsync(StoragesTableData row) async {
    String? decrypted;
    if (row.passwordCipher != null && row.passwordNonce != null) {
      try {
        decrypted = await StorageCipher.decrypt(
          row.passwordCipher!,
          row.passwordNonce!,
        );
      } catch (_) {
        decrypted = row.password;
      }
    } else {
      decrypted = row.password;
    }
    return fromDbWithPassword(row, decrypted);
  }

  StoragesTableCompanion toCompanion() {
    if (this is WebDAVStorage) {
      final s = this as WebDAVStorage;
      return StoragesTableCompanion.insert(
        id: s.id,
        dataScopeId: Value(s.dataScopeId),
        type: s.type.index,
        name: s.name,
        basePath: json.encode(s.basePath),
        host: Value(s.host),
        resolvedHost: Value(s.resolvedHost),
        resolvedHosts: Value(json.encode(s.resolvedHosts)),
        port: Value(s.port),
        username: Value(s.username),
        password: Value(s.password),
        passwordCipher: const Value(null),
        passwordNonce: const Value(null),
        https: Value(s.https),
      );
    }

    if (this is FTPStorage) {
      final s = this as FTPStorage;
      return StoragesTableCompanion.insert(
        id: s.id,
        dataScopeId: Value(s.dataScopeId),
        type: s.type.index,
        name: s.name,
        basePath: json.encode(s.basePath),
        host: Value(s.host),
        port: Value(s.port),
        username: Value(s.username),
        password: Value(s.password),
        passwordCipher: const Value(null),
        passwordNonce: const Value(null),
        https: const Value(null),
      );
    }

    final s = this as LocalStorage;
    return StoragesTableCompanion.insert(
      id: s.id,
      type: s.type.index,
      name: s.name,
      basePath: json.encode(s.basePath),
      volumeId: Value(s.volumeId),
      host: const Value(null),
      port: const Value(null),
      username: const Value(null),
      password: const Value(null),
      passwordCipher: const Value(null),
      passwordNonce: const Value(null),
      https: const Value(null),
    );
  }

  /// Async companion that encrypts the password into cipher/nonce columns.
  /// Plaintext `password` is cleared to avoid at-rest leakage.
  Future<StoragesTableCompanion> toCipherCompanion() async {
    if (this is WebDAVStorage) {
      final s = this as WebDAVStorage;
      final enc = await StorageCipher.encrypt(s.password);
      return StoragesTableCompanion.insert(
        id: s.id,
        dataScopeId: Value(s.dataScopeId),
        type: s.type.index,
        name: s.name,
        basePath: json.encode(s.basePath),
        host: Value(s.host),
        resolvedHost: Value(s.resolvedHost),
        resolvedHosts: Value(json.encode(s.resolvedHosts)),
        port: Value(s.port),
        username: Value(s.username),
        password: const Value(null),
        passwordCipher: Value(enc.cipher),
        passwordNonce: Value(enc.nonce),
        https: Value(s.https),
      );
    }

    if (this is FTPStorage) {
      final s = this as FTPStorage;
      final enc = await StorageCipher.encrypt(s.password);
      return StoragesTableCompanion.insert(
        id: s.id,
        dataScopeId: Value(s.dataScopeId),
        type: s.type.index,
        name: s.name,
        basePath: json.encode(s.basePath),
        host: Value(s.host),
        port: Value(s.port),
        username: Value(s.username),
        password: const Value(null),
        passwordCipher: Value(enc.cipher),
        passwordNonce: Value(enc.nonce),
        https: const Value(null),
      );
    }

    final s = this as LocalStorage;
    return StoragesTableCompanion.insert(
      id: s.id,
      type: s.type.index,
      name: s.name,
      basePath: json.encode(s.basePath),
      volumeId: Value(s.volumeId),
      host: const Value(null),
      port: const Value(null),
      username: const Value(null),
      password: const Value(null),
      passwordCipher: const Value(null),
      passwordNonce: const Value(null),
      https: const Value(null),
    );
  }
}
