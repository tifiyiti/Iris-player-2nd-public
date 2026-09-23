import 'dart:io';
import 'dart:typed_data';

import 'package:iris/features/app_identity/model/domain/app_identity_entry.dart';
import 'package:iris/features/app_identity/services/app_identity_paths.dart';
import 'package:iris/features/app_identity/services/shortcut_channel_service.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:path/path.dart' as p;

/// Platform facade: pins/updates one entry on the current platform.
///
/// Deep-module contract: returns null on success, or a USER-FACING error
/// string for the explanatory dialog — errors are defined out of existence,
/// never thrown into the UI layer.
Future<String?> applyEntryToPlatform(
  AppIdentityEntry entry,
  Uint8List? freshPng,
  AppLocalizations t,
) async {
  try {
    if (Platform.isAndroid) {
      return await _applyAndroid(entry, freshPng, t);
    }
    return t.entry_apply_android_only;
  } catch (e) {
    return t.entry_apply_failed('$e');
  }
}

/// Best-effort removal of platform artifacts.
/// Android pinned shortcuts cannot be removed programmatically — the
/// manager dialog explains manual long-press deletion.
Future<void> removePlatformArtifacts(AppIdentityEntry entry) async {
  // Android only: nothing to remove beyond the persisted entry row.
}

Future<String?> _applyAndroid(
  AppIdentityEntry entry,
  Uint8List? freshPng,
  AppLocalizations t,
) async {
  final service = ShortcutChannelService();
  service.ensureInitialized();
  final cap = await service.capability();
  if (!cap.sdkOk) {
    return t.entry_pin_requires_android8;
  }
  if (!cap.launcherSupportsPin) {
    return t.entry_pin_launcher_unsupported;
  }
  try {
    if (entry.imageRef.isEmpty) {
      // Name-only entry (legacy/migrated): a label update can only refresh an
      // EXISTING pinned shortcut. When none is pinned there is nothing to show,
      // so surface the missing-icon reason instead of a fake success.
      final updated = await service.updateShortcut(
        entryId: entry.id,
        name: entry.name,
      );
      if (!updated) return t.entry_icon_missing;
    } else if (freshPng != null) {
      // Native side updates in place when this id is already pinned.
      await service.pinShortcut(
        entryId: entry.id,
        name: entry.name,
        png: freshPng,
      );
    } else {
      // Re-pin of an existing entry without fresh bytes: reload the prepared
      // icon from documents dir so a missing desktop shortcut can be
      // re-created with its original artwork. If the icon file is gone too,
      // fall back to a label-only update (keeps an existing pinned shortcut
      // alive) and report a real failure when nothing was updated.
      final icon = await _readPreparedIcon(entry.imageRef);
      if (icon != null) {
        await service.pinShortcut(
          entryId: entry.id,
          name: entry.name,
          png: icon,
        );
      } else {
        final updated = await service.updateShortcut(
          entryId: entry.id,
          name: entry.name,
        );
        if (!updated) return t.entry_icon_missing;
      }
    }
    return null;
  } on ShortcutChannelException catch (e) {
    if (e.code == 'pin_failed') {
      return t.entry_pin_rejected(e.message);
    }
    return t.entry_shortcut_failed(e.message);
  }
}

Future<Uint8List?> _readPreparedIcon(String imageRef) async {
  try {
    final f = File(p.join(AppIdentityPaths.root, imageRef));
    if (!await f.exists()) return null;
    return await f.readAsBytes();
  } catch (_) {
    return null;
  }
}
