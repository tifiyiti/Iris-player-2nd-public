import 'package:flutter/material.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/warning_dialogs.dart';
import 'package:iris/utils/format_duration_hms.dart';
import 'package:iris/utils/get_localizations.dart';

/// One traversed 副音 file rendered by [showBgContinuationDialog].
///
/// [localMs] is set ONLY on the entry 副音 now continues at (the alignment
/// target); every earlier entry just shows its name + duration, so the dialog
/// reads as "the list it walked through, then where it landed".
class BgContinuationEntry {
  const BgContinuationEntry({
    required this.name,
    required this.durationMs,
    this.localMs,
  });

  final String name;
  final int durationMs;
  final int? localMs;
}

/// The cross-file 副音 continuation explainer (副音 finished before the single
/// foreground video, under [BgExhaustedAction.nextBg]).
///
/// Shown while BOTH runtimes are paused (the caller owns the pause/restore). It
/// lists the files the looping 副音 timeline passed through and the file +
/// position playback now continues at. Suppressible forever (`bgContinuation`),
/// so an uninterrupted session stops raising it; the caller then applies the
/// continuation silently.
///
/// The list is a lazy `ListView.builder` inside a height-capped box: a very long
/// 副音 queue must never build every row up front on a phone.
Future<void> showBgContinuationDialog(
  BuildContext context, {
  required List<BgContinuationEntry> entries,
  required bool fromAlign,
  bool Function(String id)? isSuppressedOverride,
  void Function(String id)? onSuppressOverride,
}) async {
  final store = useAppStore();
  final suppressed = isSuppressedOverride ??
      (id) => !shouldShowWarning(store.state.suppressedWarnings, id);
  final suppress = onSuppressOverride ?? (id) => store.suppressWarning(id);
  if (suppressed(kWarningBgContinuation)) return;

  await showDialog<void>(
    context: context,
    builder: (_) => _BgContinuationDialog(
      entries: entries,
      fromAlign: fromAlign,
      onSuppress: suppress,
    ),
  );
}

/// Whether the continuation explainer is currently suppressed (no UI). Lets the
/// caller apply the continuation silently without opening a dialog.
bool bgContinuationSuppressed(
  List<String> suppressedWarnings, {
  bool Function(String id)? isSuppressedOverride,
}) =>
    isSuppressedOverride != null
        ? isSuppressedOverride(kWarningBgContinuation)
        : !shouldShowWarning(suppressedWarnings, kWarningBgContinuation);

class _BgContinuationDialog extends StatefulWidget {
  const _BgContinuationDialog({
    required this.entries,
    required this.fromAlign,
    required this.onSuppress,
  });

  final List<BgContinuationEntry> entries;
  final bool fromAlign;
  final void Function(String id) onSuppress;

  @override
  State<_BgContinuationDialog> createState() => _BgContinuationDialogState();
}

class _BgContinuationDialogState extends State<_BgContinuationDialog> {
  bool _dontAskAgain = false;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final theme = Theme.of(context);
    final entries = widget.entries;
    // Cap the rendered rows so a huge queue cannot ask for an enormous lazy
    // viewport; the tail (where playback continues) is always kept.
    const int maxRows = 200;
    final bool truncated = entries.length > maxRows;
    final shown = truncated ? entries.sublist(entries.length - maxRows) : entries;
    final target = entries.isNotEmpty ? entries.last : null;

    return AlertDialog(
      icon: const Icon(Icons.queue_music_rounded),
      title: Text(t.bg_continuation_title),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.fromAlign
                  ? t.bg_continuation_from_align
                  : t.bg_continuation_intro,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  shrinkWrap: true,
                  itemCount: shown.length + (truncated ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (truncated && i == 0) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        child: Text(
                          t.bg_continuation_omitted,
                          style: theme.textTheme.labelSmall,
                        ),
                      );
                    }
                    final e = shown[truncated ? i - 1 : i];
                    return _row(context, e);
                  },
                ),
              ),
            ),
            if (target != null) ...[
              const SizedBox(height: 10),
              Text(
                t.bg_continuation_now_at(
                  target.name,
                  formatDurationHms(Duration(milliseconds: target.durationMs)),
                  formatDurationHms(
                      Duration(milliseconds: target.localMs ?? 0)),
                ),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
            CheckboxListTile(
              value: _dontAskAgain,
              onChanged: (v) => setState(() => _dontAskAgain = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(t.dlg_dont_ask_again),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () {
            if (_dontAskAgain) widget.onSuppress(kWarningBgContinuation);
            Navigator.of(context).pop();
          },
          child: Text(t.ok),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, BgContinuationEntry e) {
    final theme = Theme.of(context);
    final isTarget = e.localMs != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Icon(
            isTarget
                ? Icons.play_arrow_rounded
                : Icons.music_note_outlined,
            size: 16,
            color: isTarget
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              e.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: isTarget
                  ? theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.primary)
                  : theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatDurationHms(Duration(milliseconds: e.durationMs)),
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}
