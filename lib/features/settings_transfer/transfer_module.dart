import 'package:iris/features/meta_settings/meta_settings_module.dart';
import 'package:iris/features/settings_transfer/contributions/transfer_audit_contribution.dart';

class TransferModule {
  static bool _ready = false;
  static bool get ready => _ready;

  static Future<void> init() async {
    if (_ready) return;
    if (!MetaSettingsModule.ready) return;
    try {
      await MetaSettingsModule.repo.seedDefs(TransferAuditContribution.defs);
      _ready = true;
    } catch (_) {}
  }
}
