import 'package:flutter/foundation.dart';
import 'package:iris/l10n/app_localizations.dart';

// Cross-platform transfer policy: which appSettings keys migrate to which
// target platform. Single source of truth mirroring the `platforms` lists in
// the meta_settings contributions (app_settings_contribution +
// osd_settings_contribution): same-platform imports keep everything, while
// cross-platform (desktop <-> mobile) imports keep common + target-platform
// keys and skip source-platform-only keys with [kPlatformSkippedNote].
//
// Data sections other than appSettings (history, favorites, scenarios,
// tagPlay, virtualMedia, networkStorages) are platform-neutral by design —
// notably WebDAV/FTP storages migrate freely between phone and desktop —
// so they need no filtering here.

// Import-report marker for skipped source-platform-only items. The report
// dialog groups on this marker to explain the skip (not a failure).
const String kPlatformSkippedNote = '来源平台专属，已跳过';

// Envelope stamp for files predating the sourcePlatform field.
const String kTransferPlatformUnknown = 'unknown';

/// Settings-transfer platform id for a Flutter [TargetPlatform].
String transferPlatformName(TargetPlatform p) => switch (p) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.macOS => 'macos',
      _ => kTransferPlatformUnknown,
    };

/// Platform id of the running device (stamped into every export envelope).
String get currentTransferPlatformName => transferPlatformName(defaultTargetPlatform);

/// Localized display name for the transfer dialogs.
String transferPlatformDisplayName(String platform, AppLocalizations t) =>
    switch (platform) {
      'android' => t.transfer_platform_android,
      'ios' => t.transfer_platform_ios,
      'windows' => t.transfer_platform_windows,
      'linux' => t.transfer_platform_linux,
      'macos' => t.transfer_platform_macos,
      _ => t.transfer_platform_unknown,
    };

abstract final class PlatformKeyPolicy {
  static const Set<String> desktopPlatforms = {'windows', 'linux', 'macos'};
  static const Set<String> mobilePlatforms = {'android', 'ios'};

  static bool isDesktopPlatform(String p) => desktopPlatforms.contains(p);
  static bool isMobilePlatform(String p) => mobilePlatforms.contains(p);

  // Snapshot (AppState JSON) fields carrying desktop-only knobs. Mirrors the
  // windows/linux/macos SettingDefs; everything else snapshot-side is either
  // common or mobile-only (listed below).
  static const Set<String> desktopOnlySnapshotFields = {
    'autoResize',
    'keyboardShortcutScheme',
    'desktopControlBarLayout',
    'desktopCenterZonePhoneMode',
  };

  // Snapshot fields carrying mobile-only knobs (gestures, phone sliders,
  // orientation, title overlays, popup/breadcrumb). Mirrors the android
  // SettingDefs.
  static const Set<String> mobileOnlySnapshotFields = {
    'phoneLandscapeSliderType',
    'phoneLandscapeUseMode',
    'phoneOneHandedScrubberKind',
    'circleLandscapePercent',
    'circleSliderScale',
    'preferredOrientation',
    'reuseLastOrientation',
    'gestureMode',
    'landscapeGestureProfile',
    'portraitGestureProfile',
    'gestureLayoutProfiles',
    'showControlsOnPlayToPause',
    'controlsTitleConfig',
    'minimalTitleConfig',
    'defaultPopupDirection',
    'breadcrumbStartPortrait',
    'breadcrumbStartLandscape',
  };

  static bool _isDesktopOnlyAux(String key) {
    return key.startsWith('window.') ||
        key.startsWith('keybind.') ||
        key.startsWith('osd.') ||
        key == 'screenshot.desktopDir' ||
        key == 'video.desktopDisplayMode';
  }

  static bool _isMobileOnlyAux(String key) {
    return key == 'screenshot.mobileDir' ||
        key == 'video.mobileDisplayMode';
  }

  /// Whether an AppState snapshot field migrates to [targetPlatform].
  /// `unknown` (legacy unstamped files) keeps everything.
  static bool isTransferableSnapshotField(String field, String targetPlatform) {
    if (targetPlatform == kTransferPlatformUnknown) return true;
    if (desktopOnlySnapshotFields.contains(field)) {
      return isDesktopPlatform(targetPlatform);
    }
    if (mobileOnlySnapshotFields.contains(field)) {
      return isMobilePlatform(targetPlatform);
    }
    return true;
  }

  /// Whether a metadata AUX row key migrates to [targetPlatform].
  /// Shared rows (`slider.*`, `speed.*`, `virtualmedia.*`, `dialring.*`,
  // `browse.*`, `playback.*`, `scan.*`, `identity.*`, `security.*`) carry
  // either common knobs or per-platform-isolated keys, so they always move.
  // `screenshot.mobileDir` / `screenshot.desktopDir` are the exception:
  // foreign shapes (`content://` on desktop) are skipped per direction.
  static bool isTransferableAuxKey(String key, String targetPlatform) {
    if (targetPlatform == kTransferPlatformUnknown) return true;
    if (_isDesktopOnlyAux(key)) return isDesktopPlatform(targetPlatform);
    if (_isMobileOnlyAux(key)) return isMobilePlatform(targetPlatform);
    return true;
  }

  /// Non-null skip reason when [key] must not migrate to [targetPlatform].
  /// [isAuxRow] selects the AUX-row rules, otherwise the snapshot rules.
  static String? skipNoteFor(String key, String targetPlatform, {bool isAuxRow = false}) {
    final ok = isAuxRow
        ? isTransferableAuxKey(key, targetPlatform)
        : isTransferableSnapshotField(key, targetPlatform);
    return ok ? null : kPlatformSkippedNote;
  }
}
