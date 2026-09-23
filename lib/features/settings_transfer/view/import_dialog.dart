import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:iris/features/settings_transfer/engine/platform_key_policy.dart';
import 'package:iris/features/settings_transfer/engine/transfer_catalog.dart';
import 'package:iris/features/settings_transfer/model/import_resolution.dart';
import 'package:iris/features/settings_transfer/model/transfer_section.dart';
import 'package:iris/features/settings_transfer/services/transfer_crypto.dart';
import 'package:iris/features/settings_transfer/services/transfer_file_service.dart';
import 'package:iris/features/settings_transfer/services/transfer_service.dart';
import 'package:iris/features/settings_transfer/view/import_report_dialog.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/dialogs/show_message_dialog.dart';

Future<void> showTransferImportDialog(BuildContext context) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final t0 = getLocalizations(context);

  // Step 1: pick file
  String? content;
  try {
    content = await pickTransferFile();
  } catch (e) {
    await showMessageDialog(navigator, message: '${t0.import_failed}: $e', type: MessageDialogType.error);
    return;
  }
  if (content == null) {
    await showMessageDialog(navigator, message: t0.import_cancelled, type: MessageDialogType.info);
    return;
  }

  Map<String, dynamic> json;
  try {
    json = jsonDecode(content) as Map<String, dynamic>;
  } catch (e) {
    await showMessageDialog(navigator, message: t0.transfer_import_parse_failed('$e'), type: MessageDialogType.error);
    return;
  }

  // Legacy v1 detection
  final bool isLegacyV1 = json['format'] == 1 && json.containsKey('app');
  final bool isEncrypted = TransferCrypto.isEncryptedEnvelope(json);
  // Outer envelope stamp survives encryption (sections don't), so the
  // source device is known even before the passphrase prompt.
  final String sourcePlatform =
      isLegacyV1 ? kTransferPlatformUnknown : (json['sourcePlatform'] as String? ?? kTransferPlatformUnknown);
  final String targetPlatform = currentTransferPlatformName;
  final Map<String, dynamic> sections = isLegacyV1
      ? {'appSettings': json['app'], 'networkStorages': json['storage']}
      : isEncrypted
          ? {}
          : ((json['sections'] as Map?)?.cast<String, dynamic>() ?? {});

  // For encrypted, we need passphrase before showing section choices.
  String passphrase = '';
  bool obscurePass = true;

  if (isEncrypted) {
    // Prompt passphrase first
    // The settings page may have been left while the file was picked/parsed.
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final t = getLocalizations(ctx);
        return StatefulBuilder(
          builder: (_, setState) => AlertDialog(
            title: Text(t.transfer_import_decrypt_title),
            content: TextFormField(
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: t.transfer_import_pass_label,
                suffixIcon: IconButton(
                  icon: Icon(obscurePass ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => obscurePass = !obscurePass),
                ),
              ),
              obscureText: obscurePass,
              enableInteractiveSelection: true,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (v) => passphrase = v.trim(),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.import_label)),
            ],
          ),
        );
      },
    );
    if (ok != true) {
      await showMessageDialog(navigator, message: t0.import_cancelled, type: MessageDialogType.info);
      return;
    }
    if (passphrase.isEmpty) {
      await showMessageDialog(navigator, message: t0.transfer_import_pass_empty, type: MessageDialogType.error);
      return;
    }
    // Validate passphrase by trying decrypt, to give early feedback and extract sections
    try {
      final enc = (json['enc'] as Map).cast<String, dynamic>();
      final plain = await TransferCrypto.decrypt(enc: enc, passphrase: passphrase);
      final decoded = jsonDecode(plain) as Map<String, dynamic>;
      sections.clear();
      sections.addAll(decoded.cast<String, dynamic>());
    } catch (e) {
      await showMessageDialog(navigator, message: t0.transfer_import_pass_bad('$e'), type: MessageDialogType.error);
      return;
    }
  }

  // Build section choices UI
  final availableKeys = isLegacyV1
      ? ['appSettings', 'networkStorages', 'favorites']
      : sections.keys.toList();

  final selected = <String>{for (final k in availableKeys) k};
  final resolutions = <String, TransferResolution>{for (final k in availableKeys) k: defaultResolutionFor(k)};
  bool skipErrors = true;
  // Cross-family (desktop <-> mobile) imports filter appSettings down to
  // common + this device's keys; other sections migrate freely.
  final bool isCrossPlatform = sourcePlatform != kTransferPlatformUnknown &&
      sourcePlatform != targetPlatform &&
      (PlatformKeyPolicy.isDesktopPlatform(sourcePlatform) !=
          PlatformKeyPolicy.isDesktopPlatform(targetPlatform));

  // Add keys that are in file but not in availableKeys? Already.
  // Also offer all known sections not in file as disabled?
  final allKnown = TransferCatalog.allKeys;

  // Decryption/parse above awaited user input and file IO.
  if (!context.mounted) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (_, setState) {
        final t = getLocalizations(ctx);
        return AlertDialog(
          title: Text(t.import_options),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.transfer_import_route(
                      transferPlatformDisplayName(sourcePlatform, t),
                      transferPlatformDisplayName(targetPlatform, t)),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                if (isCrossPlatform)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(t.transfer_import_cross_note,
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
                const SizedBox(height: 8),
                if (isLegacyV1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(t.transfer_import_legacy_note,
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
                for (final key in availableKeys)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CheckboxListTile(
                        value: selected.contains(key),
                        title: Text(TransferSectionX.fromKey(key)?.label(t) ?? key),
                        subtitle: Text(TransferSectionX.fromKey(key)?.description(t) ?? ''),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            selected.add(key);
                          } else {
                            selected.remove(key);
                          }
                        }),
                      ),
                      if (selected.contains(key))
                        Padding(
                          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                          child: DropdownButton<TransferResolution>(
                            value: resolutions[key],
                            isExpanded: true,
                            items: (kSectionResolutions[key] ?? TransferResolution.values)
                                .map((r) => DropdownMenuItem(value: r, child: Text(r.label(t))))
                                .toList(),
                            onChanged: (v) => setState(() => resolutions[key] = v!),
                          ),
                        ),
                    ],
                  ),
                // Show not-in-file sections as disabled
                for (final key in allKnown.where((k) => !availableKeys.contains(k)))
                  ListTile(
                    enabled: false,
                    title: Text(
                        '${TransferSectionX.fromKey(key)?.label(t) ?? key}${t.transfer_sec_missing_suffix}'),
                  ),
                const Divider(),
                SwitchListTile(
                  title: Text(t.transfer_import_skip_errors),
                  value: skipErrors,
                  onChanged: (v) => setState(() => skipErrors = v),
                ),
                Text(t.transfer_import_skip_errors_note,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.import_label)),
          ],
        );
      },
    ),
  );

  if (confirmed != true) return;

  if (selected.isEmpty) {
    await showMessageDialog(navigator, message: t0.import_nothing_selected, type: MessageDialogType.error);
    return;
  }

  // Build final resolutions map: unselected => skip
  final finalResolutions = <String, TransferResolution>{};
  for (final k in availableKeys) {
    finalResolutions[k] = selected.contains(k) ? (resolutions[k] ?? defaultResolutionFor(k)) : TransferResolution.skip;
  }

  // Execute import
  // Need to reconstruct raw with correct sections for TransferService.
  // If encrypted, we already decrypted sections, so we need to re-encode raw as plain.
  String rawForImport;
  if (isEncrypted) {
    // Rebuild a plain envelope json with decrypted sections for the service's decrypt path
    // Simpler: call service with original raw + passphrase; it will decrypt again.
    rawForImport = content;
  } else if (isLegacyV1) {
    rawForImport = content;
  } else {
    rawForImport = content;
  }

  try {
    final report = await TransferService.importFromJson(
      rawForImport,
      resolutions: finalResolutions,
      skipErrors: skipErrors,
      passphrase: isEncrypted ? passphrase : null,
    );
    if (navigator.mounted) {
      // Root-navigator context stays valid even if the settings page that
      // launched the import was closed mid-dialog.
      await showImportReportDialog(navigator.context, report);
    }
  } catch (e) {
    await showMessageDialog(navigator, message: '${t0.import_failed}: $e', type: MessageDialogType.error);
  }
}
