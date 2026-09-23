import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/features/media_library/scan/probe/scan_probe_preference.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/utils/get_localizations.dart';

/// Shown before a recursive scan starts.
///
/// Returns:
/// - `null`  → user cancelled, do not start the scan;
/// - `true`  → start with deep media-info probe enabled;
/// - `false` → start plain scan.
Future<bool?> showScanOptionsDialog(BuildContext context,
    {required StorageType storageType}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => ScanOptionsDialog(storageType: storageType),
  );
}

/// Immediately-visible time estimate for the probe checkbox (general-case
/// magnitudes, no pre-count wait): platform × storage aware so each surface
/// states its own cost model up front.
String scanProbeEstimateText({
  required AppLocalizations t,
  required bool isWindows,
  required bool isAndroid,
  required StorageType storageType,
}) {
  if (storageType == StorageType.ftp ||
      storageType == StorageType.webdav ||
      storageType == StorageType.network) {
    return t.scan_estimate_remote;
  }
  if (isWindows) {
    return t.scan_estimate_win;
  }
  if (isAndroid) {
    return t.scan_estimate_android;
  }
  return t.scan_estimate_none;
}

class ScanOptionsDialog extends HookWidget {
  const ScanOptionsDialog({super.key, required this.storageType});

  final StorageType storageType;

  @override
  Widget build(BuildContext context) {
    // Probe defaults ON (第一次未保存过时勾选 — "默认勾选扫描时间"); an
    // explicit earlier choice overrides the default.
    final probe = useState(true);
    final loaded = useState(false);

    // Restore last confirmed choice once.
    useEffect(() {
      var cancelled = false;
      ScanProbePreference.load().then((v) {
        if (!cancelled) {
          if (v != null) probe.value = v;
        }
        if (!cancelled) loaded.value = true;
      });
      return () => cancelled = true;
    }, const []);

    final theme = Theme.of(context);
    final t = getLocalizations(context);
    final bodySmall = theme.textTheme.bodySmall;

    final strategyText = Platform.isWindows
        ? t.scan_strategy_win
        : Platform.isAndroid
            ? t.scan_strategy_android
            : t.scan_strategy_none;

    return AlertDialog(
      title: Text(t.scan_title),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: loaded.value ? probe.value : null,
              tristate: true,
              onChanged: (v) =>
                  probe.value = v == true,
              title: Text(t.scan_probe_label),
            ),
            const SizedBox(height: 8),
            Text(t.scan_purpose, style: bodySmall),
            const SizedBox(height: 8),
            Text(strategyText, style: bodySmall),
            const SizedBox(height: 8),
            Text(
              scanProbeEstimateText(
                t: t,
                isWindows: Platform.isWindows,
                isAndroid: Platform.isAndroid,
                storageType: storageType,
              ),
              style: bodySmall,
            ),
            const SizedBox(height: 8),
            Text(t.scan_caveat, style: bodySmall),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(t.scan_cancel),
        ),
        ElevatedButton(
          onPressed: () async {
            await ScanProbePreference.save(probe.value);
            if (context.mounted) Navigator.of(context).pop(probe.value);
          },
          child: Text(t.scan_start),
        ),
      ],
    );
  }
}
