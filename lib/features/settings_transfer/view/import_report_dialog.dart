import 'package:flutter/material.dart';
import 'package:iris/features/settings_transfer/engine/platform_key_policy.dart';
import 'package:iris/features/settings_transfer/model/transfer_report.dart';
import 'package:iris/features/settings_transfer/model/transfer_section.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/utils/get_localizations.dart';

Future<void> showImportReportDialog(BuildContext context, TransferReport report) async {
  // Source-platform-only items are reported ok with the skip marker — surface
  // their count so cross-platform users understand they are not failures.
  final skippedPlatformCount =
      report.items.where((e) => e.error != null && e.error!.contains(kPlatformSkippedNote)).length;
  await showDialog(
    context: context,
    builder: (ctx) {
      final t = getLocalizations(ctx);
      return AlertDialog(
        title: Text(report.hasFailures ? t.transfer_report_partial_title : t.import_success),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.transfer_report_counts(report.okCount, report.failCount)),
              if (skippedPlatformCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(t.transfer_report_platform_skipped(skippedPlatformCount),
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ),
              const SizedBox(height: 12),
              for (final entry in report.summary.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          t.transfer_report_section_line(
                              TransferSectionX.fromKey(entry.key)?.label(t) ?? entry.key,
                              entry.value.ok,
                              entry.value.fail),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      for (final item in report.bySection[entry.key] ?? [])
                        Padding(
                          padding: const EdgeInsets.only(left: 8, top: 2),
                          child: Text(
                            '${item.ok ? "✓" : "✗"} ${item.label}${item.error == null ? "" : " — ${_displayError(item.error!, t)}"}',
                            style: TextStyle(
                              fontSize: 12,
                              color: item.ok ? Colors.green.shade700 : Colors.red.shade700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              if (report.skippedErrors && report.hasFailures)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(t.transfer_report_skipped_note,
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.ok)),
        ],
      );
    },
  );
}

/// Maps internal stable error markers to localized display text; unknown
/// errors (exception strings) pass through untouched.
String _displayError(String error, AppLocalizations t) {
  if (error.contains(kPlatformSkippedNote)) {
    return error.replaceAll(kPlatformSkippedNote, t.transfer_platform_skipped_note);
  }
  return error;
}
