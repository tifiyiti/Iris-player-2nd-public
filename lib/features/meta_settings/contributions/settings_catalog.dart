import 'package:iris/features/app_identity/contributions/app_identity_settings_contribution.dart';
import 'package:iris/features/background_playback/contributions/background_playback_settings_contribution.dart';
import 'package:iris/features/meta_settings/contributions/app_settings_contribution.dart';
import 'package:iris/features/meta_settings/contributions/merger.dart';
import 'package:iris/features/meta_settings/contributions/osd_settings_contribution.dart';
import 'package:iris/features/meta_settings/contributions/scan_settings_contribution.dart';
import 'package:iris/features/meta_settings/model/setting_def.dart';
import 'package:iris/features/playback_tools/contributions/screenshot_settings_contribution.dart';
import 'package:iris/features/settings_transfer/contributions/transfer_audit_contribution.dart';
import 'package:iris/features/speed/contributions/speed_settings_contribution.dart';
import 'package:iris/features/tag_play/contributions/tag_play_settings_contribution.dart';
import 'package:iris/features/virtual_media/contributions/virtual_media_settings_contribution.dart';

/// Single authority for the merged settings catalog.
///
/// Both consumers — the DB def-mirror seeding (MetaSettingsModule.init) and
/// the renderer (MetaSettingsPage) — MUST read from here so a contribution
/// added in exactly one place is validated once, seeded once, and rendered
/// everywhere.
abstract final class SettingsCatalog {
  static final List<SettingDef> defs = SettingsContributionMerger.merge([
    AppSettingsContribution.defs,
    ScanSettingsContribution.defs,
    AppIdentitySettingsContribution.defs,
    OsdSettingsContribution.defs,
    SpeedSettingsContribution.defs,
    ScreenshotSettingsContribution.defs,
    VirtualMediaSettingsContribution.defs,
    TagPlaySettingsContribution.defs,
    BackgroundPlaybackSettingsContribution.defs,
    TransferAuditContribution.defs,
  ]);
}
