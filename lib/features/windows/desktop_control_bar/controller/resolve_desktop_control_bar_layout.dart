import 'package:iris/models/store/app_state.dart';

/// Resolves the EFFECTIVE desktop control-bar layout.
///
/// The metadata gate owns the read path: while it is OFF the stored value is
/// ignored and the classic single-line bar applies — a stale `stacked`
/// selection carried in an old blob (or a default that outlived a rollback)
/// must never leak new behavior to users who left the metadata system.
/// Mirrors `resolveKeyboardScheme`.
DesktopControlBarLayout resolveDesktopControlBarLayout({
  required DesktopControlBarLayout stored,
  required bool metadataEnabled,
}) {
  if (!metadataEnabled) return DesktopControlBarLayout.singleLine;
  return stored;
}
