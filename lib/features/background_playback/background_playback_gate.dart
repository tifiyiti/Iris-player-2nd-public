import 'package:iris/store/use_app_store.dart';

/// 副音播放 feature gate (meta-driven era only).
///
/// Same shape as [TagPlayGate]: the subsystem binds to the metadata stack —
/// it is entirely absent for legacy-persistence users (More-menu entry
/// hidden; a gate-off invocation degrades to an explanatory dialog).
abstract final class BackgroundPlaybackGate {
  static bool get enabled {
    final app = useAppStore().state;
    return !app.useLegacyStoragePersistence && app.useMetadataSettings;
  }

  /// DEPRECATED — sub_media §2.
  ///
  /// The legacy More-menu 副音 entries (launch + float-panel toggle) are sealed
  /// behind this permanently-false flag: the code is kept verbatim so the old
  /// path can be restored for rollback, but nothing enters it any more — the
  /// control-bar 副音 menu (§4/§5) owns those user intents now. Delete the
  /// sealed items (and [BackgroundPlaybackActions.open]) once the new menu has
  /// proven stable in a release.
  static const bool legacyMoreMenuEntryEnabled = false;
}
