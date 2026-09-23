// Transfer sections — each is independently selectable, versioned and
// tolerant (one bad item/selection never blocks others).
import 'package:iris/l10n/app_localizations.dart';

enum TransferSection {
  appSettings,
  history,
  favorites,
  scenarios,
  tagPlay,
  virtualMedia,
  networkStorages,
}

extension TransferSectionX on TransferSection {
  String get key => switch (this) {
        TransferSection.appSettings => 'appSettings',
        TransferSection.history => 'history',
        TransferSection.favorites => 'favorites',
        TransferSection.scenarios => 'scenarios',
        TransferSection.tagPlay => 'tagPlay',
        TransferSection.virtualMedia => 'virtualMedia',
        TransferSection.networkStorages => 'networkStorages',
      };

  String label(AppLocalizations t) => switch (this) {
        TransferSection.appSettings => t.transfer_sec_app_settings,
        TransferSection.history => t.transfer_sec_history,
        TransferSection.favorites => t.transfer_sec_favorites,
        TransferSection.scenarios => t.transfer_sec_scenarios,
        TransferSection.tagPlay => t.transfer_sec_tag_play,
        TransferSection.virtualMedia => t.transfer_sec_virtual_media,
        TransferSection.networkStorages => t.transfer_sec_network,
      };

  String description(AppLocalizations t) => switch (this) {
        TransferSection.appSettings => t.transfer_sec_app_settings_desc,
        TransferSection.history => t.transfer_sec_history_desc,
        TransferSection.favorites => t.transfer_sec_favorites_desc,
        TransferSection.scenarios => t.transfer_sec_scenarios_desc,
        TransferSection.tagPlay => t.transfer_sec_tag_play_desc,
        TransferSection.virtualMedia => t.transfer_sec_virtual_media_desc,
        TransferSection.networkStorages => t.transfer_sec_network_desc,
      };

  int get subVersion => 1;

  static TransferSection? fromKey(String k) {
    for (final s in TransferSection.values) {
      if (s.key == k) return s;
    }
    return null;
  }
}
