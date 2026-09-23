import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:iris/models/store/export_bundle.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/dialogs/show_message_dialog.dart';

Future<void> showExportDialog(BuildContext context) async {
  bool exportApp = true;
  bool exportStorage = true;

  final navigator = Navigator.of(context, rootNavigator: true);

  await showDialog(
    context: context,
    builder: (ctx) {
      final t = getLocalizations(ctx);

      return StatefulBuilder(
        builder: (_, setState) => AlertDialog(
          title: Text(getLocalizations(ctx).export_options),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                value: exportApp,
                title: Text(t.export_import_app_settings),
                onChanged: (v) => setState(() => exportApp = v!),
              ),
              CheckboxListTile(
                value: exportStorage,
                title: Text(t.storage_favorites),
                onChanged: (v) => setState(() => exportStorage = v!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
            ElevatedButton(
              child: Text(t.export_label),
              onPressed: () async {
                // 1 Capture localization BEFORE any await
                final t = getLocalizations(context);

                Navigator.pop(ctx); // close dialog first

                if (!exportApp && !exportStorage) {
                  await showMessageDialog(
                    navigator,
                    message: t.export_nothing_selected,
                    type: MessageDialogType.error,
                  );
                  return;
                }
                try {
                  // 2 Build export data
                  final data = await SettingsTransferService.buildExport(
                    exportApp: exportApp,
                    exportStorage: exportStorage,
                  );

                  final jsonString = const JsonEncoder.withIndent('  ').convert(data);

                  // 3 Get default filename with app id
                  final fileName = await getDefaultExportFileName();

                  // 4 Save file

                  await exportToFile(jsonString, fileName);
                  await showMessageDialog(
                    navigator,
                    message: t.export_success,
                    type: MessageDialogType.success,
                  );
                } catch (e) {
                  await showMessageDialog(
                    navigator,
                    message: t.export_failed,
                    type: MessageDialogType.error,
                  );
                }
              },
            ),
          ],
        ),
      );
    },
  );
}

enum StorageImportMode { append, override }

Future<void> showImportDialog(BuildContext context) async {
  bool importApp = true;
  bool importStorage = true;
  bool overrideStorage = false;

  final navigator = Navigator.of(context, rootNavigator: true);

  await showDialog(
    context: context,
    builder: (ctx) {
      final t = getLocalizations(ctx);

      return StatefulBuilder(
        builder: (_, setState) => AlertDialog(
          title: Text(getLocalizations(ctx).import_options),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                value: importApp,
                title: Text(t.export_import_app_settings),
                onChanged: (v) => setState(() => importApp = v!),
              ),
              CheckboxListTile(
                value: importStorage,
                title: Text(t.storage_favorites),
                onChanged: (v) => setState(() => importStorage = v!),
              ),
              if (importStorage)
                SwitchListTile(
                  title: Text(t.import_override),
                  subtitle: Text(t.import_override_hint),
                  value: overrideStorage,
                  onChanged: (v) => setState(() => overrideStorage = v),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(t.cancel),
            ),
            ElevatedButton(
              child: Text(t.import_label),
              onPressed: () async {
                final t = getLocalizations(context);

                Navigator.pop(ctx);

                if (!importApp && !importStorage) {
                  await showMessageDialog(
                    navigator,
                    message: t.import_nothing_selected,
                    type: MessageDialogType.error,
                  );
                  return;
                }

                try {
                  final content = await importFromFile();
                  if (content == null) {
                    await showMessageDialog(
                      navigator,
                      message: t.import_cancelled,
                      type: MessageDialogType.info,
                    );
                    return;
                  }

                  final json = jsonDecode(content);
                  if (json is! Map<String, dynamic>) {
                    // internal error signaling, not user-facing content.
                    throw Exception('Invalid file');
                  }

                  await SettingsTransferService.importFromJson(
                    json,
                    importApp: importApp,
                    importStorage: importStorage,
                    overrideStorage: overrideStorage,
                  );

                  await showMessageDialog(
                    navigator,
                    message: t.import_success, // ✅ success
                    type: MessageDialogType.success,
                  );
                } catch (e) {
                  await showMessageDialog(
                    navigator,
                    message: '${t.import_failed}: $e', // ❌ error
                    type: MessageDialogType.error,
                  );
                }
              },
            ),
          ],
        ),
      );
    },
  );
}
