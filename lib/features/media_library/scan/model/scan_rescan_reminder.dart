import 'package:iris/features/meta_settings/meta_settings_module.dart';
import 'package:iris/store/use_app_store.dart';

/// The "距上次完整扫描多久后提醒重扫" preference.
///
/// Stored as `scan.rescanReminderMinutes` AUX row (meta-driven only).
/// Default 120 minutes (2h00m). Gate-off / legacy → default.
abstract final class ScanRescanReminder {
  static const String key = 'scan.rescanReminderMinutes';
  static const int defaultMinutes = 120;

  static Future<int> load() async {
    if (!useAppStore().state.useMetadataSettings || !MetaSettingsModule.ready) {
      return defaultMinutes;
    }
    try {
      final rows = await MetaSettingsModule.repo.loadRawValues();
      final raw = rows[key];
      if (raw == null || raw.isEmpty) return defaultMinutes;
      final v = int.tryParse(raw);
      return (v == null || v < 0) ? defaultMinutes : v;
    } catch (_) {
      return defaultMinutes;
    }
  }

  static Future<void> save(int minutes) async {
    await MetaSettingsModule.persistAuxRow(key, '$minutes');
  }
}

/// Convenience for the play gate.
Future<int> scanReminderMinutes() => ScanRescanReminder.load();
