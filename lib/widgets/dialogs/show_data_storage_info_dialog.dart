import 'package:flutter/material.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/platform.dart';

/// One explainer block of the data-storage dialog.
typedef StorageInfoSection = ({String header, String body});

/// Pure decision for which explainer layout to render.
///
/// `windows: true` describes the portable-edition folder layout; the generic
/// branch covers Android/iOS/Linux/macOS where data lives in app-private
/// storage and no portable mode exists.
List<StorageInfoSection> storageInfoSections({
  required bool windows,
  required AppLocalizations t,
}) {
  if (windows) {
    return [
      (header: t.dlg_storage_portable_header, body: t.dlg_storage_portable_body),
      (header: t.dlg_storage_migrate_header, body: t.dlg_storage_migrate_body),
      (
        header: t.dlg_storage_password_header,
        body: t.dlg_storage_password_body_win,
      ),
      (
        header: t.dlg_storage_security_header,
        body: t.dlg_storage_security_body_win,
      ),
      (
        header: t.dlg_storage_advanced_header,
        body: t.dlg_storage_advanced_body,
      ),
    ];
  }
  return [
    (
      header: t.dlg_storage_location_header,
      body: t.dlg_storage_location_body,
    ),
    (
      header: t.dlg_storage_device_header,
      body: t.dlg_storage_device_body,
    ),
    (
      header: t.dlg_storage_password_header,
      body: t.dlg_storage_password_body_generic,
    ),
    (
      header: t.dlg_storage_security_header,
      body: t.dlg_storage_security_body_generic,
    ),
  ];
}

/// Platform-adaptive explainer for where IRIS keeps its data and how
/// network-storage credentials are protected. Reachable from
/// Settings → About on every platform; [windows] forces a layout for
/// testing (defaults to the runtime platform check).
Future<void> showDataStorageInfoDialog(
  BuildContext context, {
  bool? windows,
}) {
  final useWindowsLayout = windows ?? isWindows;
  final sections =
      storageInfoSections(windows: useWindowsLayout, t: getLocalizations(context));

  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final colorScheme = Theme.of(ctx).colorScheme;
      final textTheme = Theme.of(ctx).textTheme;

      Widget section(StorageInfoSection s) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(s.header, style: textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(s.body, style: textTheme.bodyMedium),
              ],
            ),
          );

      return AlertDialog(
        icon: Icon(Icons.enhanced_encryption_outlined,
            color: colorScheme.primary),
        title: Text(getLocalizations(ctx).dlg_storage_info_title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final s in sections) section(s),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(getLocalizations(ctx).dlg_storage_info_got_it),
          ),
        ],
      );
    },
  );
}
