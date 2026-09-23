import 'dart:convert';

import 'package:iris/features/meta_settings/data/value_codec.dart';
import 'package:iris/features/meta_settings/model/db/repositories/settings_db_repository.dart';
import 'package:iris/models/db/app_database.dart' show SettingValuesTableCompanion;

/// One-time migration of the legacy secure-storage blob into setting_values.
///
/// IDEMPOTENCE: runs only when the value table is EMPTY. The first gate-on
/// boot performs the import; afterwards the DB is authoritative for the gate
/// period and re-importing would clobber newer user changes.
class LegacyBlobImporter {
  final SettingsDbRepository repo;
  LegacyBlobImporter(this.repo);

  /// Returns true when an import actually happened.
  Future<bool> importIfNeeded(Map<String, dynamic> legacyJson) async {
    if (legacyJson.isEmpty) return false;
    if (await repo.hasAnyValue()) return false;

    final entries = <SettingValuesTableCompanion>[];
    legacyJson.forEach((field, value) {
      try {
        entries.add(SettingValuesTableCompanion.insert(
          key: 'app.$field',
          value: jsonEncode(value),
        ));
      } catch (e) {
        metaLog.w('LegacyBlobImporter($field): $e');
      }
    });

    await repo.replaceAllRawEntries(entries);
    metaLog.i('LegacyBlobImporter: imported ${entries.length} settings rows');
    return entries.isNotEmpty;
  }
}
