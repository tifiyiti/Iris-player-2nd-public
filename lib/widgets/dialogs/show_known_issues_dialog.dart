import 'package:flutter/material.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/platform.dart';

/// One known-issue block of the known-issues dialog.
typedef KnownIssueSection = ({String header, String body});

/// Pure decision for which known-issue entries to show.
///
/// Platform-filtered so each entry is only surfaced where it applies; new
/// known issues are added here (plus their ARB keys) without touching the UI.
/// An empty result renders the [AppLocalizations.dlg_known_issues_none]
/// fallback.
List<KnownIssueSection> knownIssueSections({
  required bool windows,
  required AppLocalizations t,
}) => [
      if (windows) ...[
        (
          header: t.dlg_known_issues_fullscreen_header,
          body: t.dlg_known_issues_fullscreen_body,
        ),
        (
          header: t.dlg_known_issues_thread_header,
          body: t.dlg_known_issues_thread_body,
        ),
        (
          header: t.dlg_known_issues_vm_delete_header,
          body: t.dlg_known_issues_vm_delete_body,
        ),
      ],
      (
        header: t.dlg_known_issues_mediakit_header,
        body: t.dlg_known_issues_mediakit_body,
      ),
      (
        header: t.dlg_known_issues_vm_scale_header,
        body: t.dlg_known_issues_vm_scale_body,
      ),
      (
        header: t.dlg_known_issues_vm_scale_fix_header,
        body: t.dlg_known_issues_vm_scale_fix_body,
      ),
      // Platform-independent: the scenario queue's multi-select gate applies on
      // every platform (unlike the desktop-only delete entry above).
      (
        header: t.dlg_known_issues_vm_multiselect_header,
        body: t.dlg_known_issues_vm_multiselect_body,
      ),
    ];

/// Read-only explainer listing the project's known issues and their
/// workarounds. Reachable from Settings → About on every platform; [windows]
/// forces the Windows layout for testing (defaults to the runtime platform).
Future<void> showKnownIssuesDialog(
  BuildContext context, {
  bool? windows,
}) {
  final useWindowsLayout = windows ?? isWindows;
  final sections = knownIssueSections(
    windows: useWindowsLayout,
    t: getLocalizations(context),
  );

  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final colorScheme = Theme.of(ctx).colorScheme;
      final textTheme = Theme.of(ctx).textTheme;
      final t = getLocalizations(ctx);

      Widget section(KnownIssueSection s) => Padding(
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
        icon: Icon(Icons.bug_report_rounded, color: colorScheme.primary),
        title: Text(t.dlg_known_issues_title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (sections.isEmpty)
                Text(t.dlg_known_issues_none, style: textTheme.bodyMedium)
              else
                for (final s in sections) section(s),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t.dlg_known_issues_got_it),
          ),
        ],
      );
    },
  );
}
