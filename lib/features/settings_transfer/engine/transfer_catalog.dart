import 'package:iris/features/settings_transfer/engine/app_settings_coder.dart';
import 'package:iris/features/settings_transfer/engine/favorites_coder.dart';
import 'package:iris/features/settings_transfer/engine/history_coder.dart';
import 'package:iris/features/settings_transfer/engine/network_storage_coder.dart';
import 'package:iris/features/settings_transfer/engine/scenario_coder.dart';
import 'package:iris/features/settings_transfer/engine/section_coder.dart';
import 'package:iris/features/settings_transfer/engine/tag_play_coder.dart';
import 'package:iris/features/settings_transfer/engine/virtual_media_coder.dart';
import 'package:iris/features/settings_transfer/model/transfer_exclusion.dart';

class TransferCatalog {
  static final Map<String, SectionCoder> coders = {
    'appSettings': AppSettingsCoder(),
    'history': HistoryCoder(),
    'favorites': FavoritesCoder(),
    'scenarios': ScenarioCoder(),
    'tagPlay': TagPlayCoder(),
    'virtualMedia': VirtualMediaCoder(),
    'networkStorages': NetworkStorageCoder(),
  };

  static List<String> get allKeys => coders.keys.toList();
  static List<TransferExclusion> get exclusions => kTransferExclusions;

  static SectionCoder? coderFor(String key) => coders[key];
}
