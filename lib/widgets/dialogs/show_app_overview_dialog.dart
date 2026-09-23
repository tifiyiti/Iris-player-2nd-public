import 'package:flutter/material.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/warning_dialogs.dart';
import 'package:iris/utils/get_localizations.dart';

/// Tour of the features that set IRIS apart from a plain video player.
///
/// Two doors share one dialog body:
///  - [firstRun] = true — the automatic first-launch notice. Hidden once
///    [kWarningAppOverview] is suppressed, and the "don't show again" box
///    starts TICKED so a one-time tour is dismissed for good by default; the
///    user can restore it from Settings → Warning dialogs.
///  - manual — opened from Settings → About; always shows and carries no
///    suppression box (it is an explicit request, not a notice).
Future<void> showAppOverviewDialog(
  BuildContext context, {
  bool firstRun = false,
  bool Function(String id)? isSuppressedOverride,
  void Function(String id)? onSuppressOverride,
}) async {
  if (firstRun) {
    final store = useAppStore();
    final suppressed = isSuppressedOverride ??
        (id) => !shouldShowWarning(store.state.suppressedWarnings, id);
    if (suppressed(kWarningAppOverview)) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _AppOverviewDialog(
        onSuppress: onSuppressOverride ?? store.suppressWarning,
        showDontAsk: true,
      ),
    );
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (_) => const _AppOverviewDialog(),
  );
}

class _AppOverviewDialog extends StatefulWidget {
  const _AppOverviewDialog({this.onSuppress, this.showDontAsk = false});

  final void Function(String id)? onSuppress;
  final bool showDontAsk;

  @override
  State<_AppOverviewDialog> createState() => _AppOverviewDialogState();
}

class _AppOverviewDialogState extends State<_AppOverviewDialog> {
  // Default-checked: the tour is genuinely one-time, and the settings panel
  // can always bring it back.
  bool _dontAskAgain = true;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    final sections = <(IconData, String, String)>[
      (
        Icons.playlist_play_rounded,
        t.app_overview_scenario_title,
        t.app_overview_scenario_body,
      ),
      (
        Icons.local_offer_outlined,
        t.app_overview_tag_title,
        t.app_overview_tag_body,
      ),
      (
        Icons.video_collection_outlined,
        t.app_overview_vm_title,
        t.app_overview_vm_body,
      ),
      (
        Icons.graphic_eq_rounded,
        t.app_overview_bg_title,
        t.app_overview_bg_body,
      ),
      (
        Icons.alternate_email_rounded,
        t.app_overview_identity_title,
        t.app_overview_identity_body,
      ),
      (
        Icons.video_library_outlined,
        t.app_overview_library_title,
        t.app_overview_library_body,
      ),
      (
        Icons.keyboard_alt_outlined,
        t.app_overview_desktop_title,
        t.app_overview_desktop_body,
      ),
      (
        Icons.phone_android_rounded,
        t.app_overview_phone_title,
        t.app_overview_phone_body,
      ),
    ];

    return PopScope(
      // Persist on ANY dismissal (OK / barrier tap / Esc / back), not just the
      // OK button: the box is ticked by default, so a non-OK close must still
      // suppress — otherwise the modal reappears every launch and blocks every
      // player shortcut behind its route. `onPopInvokedWithResult` fires at pop
      // time for every path, so the suppression is observable immediately.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && widget.showDontAsk && _dontAskAgain) {
          widget.onSuppress?.call(kWarningAppOverview);
        }
      },
      child: AlertDialog(
        icon: const Icon(Icons.explore_rounded),
        title: Text(t.app_overview_title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 520),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.app_overview_intro, style: textTheme.bodyMedium),
                const SizedBox(height: 12),
                for (final section in sections) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2, right: 8),
                        child: Icon(section.$1,
                            size: 18, color: colorScheme.primary),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(section.$2,
                                style: textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(section.$3, style: textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                if (widget.showDontAsk)
                  CheckboxListTile(
                    value: _dontAskAgain,
                    onChanged: (value) =>
                        setState(() => _dontAskAgain = value ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(t.dlg_dont_ask_again),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t.ok),
          ),
        ],
      ),
    );
  }
}
