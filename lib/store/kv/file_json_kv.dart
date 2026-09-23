import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:iris/store/kv/kv_store.dart';
import 'package:iris/utils/logger.dart';
import 'package:synchronized/synchronized.dart';

final areaKeyLog = AreaKeyLog(LogKeys.legacyStore);

/// JSON-file-backed [KvStore] for portable mode.
///
/// Durability model: the whole map is rewritten atomically on every write
/// (sibling `.tmp` + rename) — state blobs are small, so full rewrite keeps
/// the format trivially debuggable and crash-safe (a torn `.tmp` never
/// touches the live file).
///
/// Corruption containment: an unparsable store file is moved aside
/// (`kv.json.corrupt-<ts>`) and the store starts empty instead of throwing.
class FileJsonKv implements KvStore {
  FileJsonKv({required this.filePath});

  /// Absolute path of the backing JSON file (e.g. `<userdata>/settings/kv.json`).
  final String filePath;

  final Map<String, String> _values = {};
  bool _loaded = false;
  final Lock _lock = Lock();

  @override
  Future<String?> read({required String key}) =>
      _lock.synchronized(() async {
        await _ensureLoadedLocked();
        return _values[key];
      });

  @override
  Future<void> write({required String key, required String value}) =>
      _lock.synchronized(() async {
        await _ensureLoadedLocked();
        _values[key] = value;
        await _persistLocked();
      });

  @override
  Future<void> delete({required String key}) => _lock.synchronized(() async {
        await _ensureLoadedLocked();
        if (_values.remove(key) != null) {
          await _persistLocked();
        }
      });

  @override
  Future<bool> containsKey({required String key}) =>
      _lock.synchronized(() async {
        await _ensureLoadedLocked();
        return _values.containsKey(key);
      });

  @override
  Future<Map<String, String>> readAll() => _lock.synchronized(() async {
        await _ensureLoadedLocked();
        return Map.of(_values);
      });

  Future<void> _ensureLoadedLocked() async {
    if (_loaded) return;

    final file = File(filePath);
    if (!await file.exists()) {
      // Nothing on disk yet: an authoritative empty store.
      _loaded = true;
      return;
    }

    // A read failure must NOT be treated as an empty store: marking `_loaded`
    // here would let the next write rewrite the file with only the new key,
    // destroying every other persisted value. Rethrowing instead keeps the
    // store unloaded, so the caller's durability gate disables writes until a
    // real read succeeds.
    final String raw = await readRaw(file);

    try {
      final decoded = json.decode(raw) as Map<String, dynamic>;
      _values
        ..clear()
        ..addAll(decoded.cast<String, String>());
    } catch (e) {
      // Preserve the evidence, then start from a clean slate.
      final backupPath =
          '$filePath.corrupt-${DateTime.now().millisecondsSinceEpoch}';
      try {
        await file.rename(backupPath);
        areaKeyLog.e('FileJsonKv corrupt store backed aside as '
            '$backupPath: $e');
      } catch (renameError) {
        areaKeyLog.e('FileJsonKv corrupt store could not be backed aside: '
            '$renameError');
      }
      _values.clear();
    }
    _loaded = true;
  }

  /// Reads the whole backing file. Overridable so tests can simulate a
  /// transient IO failure (locked file, AV scan) that must not be mistaken
  /// for an empty store.
  @visibleForTesting
  Future<String> readRaw(File file) => file.readAsString();

  Future<void> _persistLocked() async {
    final tmp = File('$filePath.tmp');
    await tmp.writeAsString(json.encode(_values), flush: true);
    await tmp.rename(filePath);
  }

  /// Test isolation: drop in-memory cache so a fresh load re-reads disk.
  @visibleForTesting
  void resetCacheForTest() {
    _values.clear();
    _loaded = false;
  }
}
