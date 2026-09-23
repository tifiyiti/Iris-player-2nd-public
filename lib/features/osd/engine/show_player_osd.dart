import 'package:iris/features/meta_settings/engine/osd_resolver.dart';
import 'package:iris/features/meta_settings/meta_settings_module.dart';
import 'package:iris/features/osd/model/osd_entry.dart';
import 'package:iris/features/osd/store/osd_store.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:iris/utils/platform.dart';

/// UI-facing OSD push (control-bar buttons, gestures) — mirrors the keyboard
/// executor's `_showOsd` gate: desktop-only, `osd.enabled` +
/// `osd.visibilityMode` respected, duration from `osdDurationMs`.
///
/// The keyboard executor keeps its private copy (method-scoped); this shared
/// helper exists so button-driven mode changes report the SAME transient
/// feedback as their keyboard counterparts (业界标准：模式变更即时居中反馈).
void showPlayerOsd(OsdEntry entry) {
  if (!isDesktop) return;
  final app = useAppStore().state;
  final enabled = app.useMetadataSettings && MetaSettingsModule.ready;
  if (!resolveOsdShouldShow(
    app,
    enabled,
    isShowControl: usePlayerUiStore().state.isShowControl,
  )) {
    return;
  }
  useOsdStore().show(
    entry,
    duration: Duration(milliseconds: app.osdDurationMs.clamp(800, 5000)),
  );
}
