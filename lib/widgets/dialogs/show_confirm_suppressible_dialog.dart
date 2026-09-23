import 'package:flutter/material.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/warning_dialogs.dart';
import 'package:iris/utils/get_localizations.dart';

/// Reusable warning confirmation with an OPTIONAL "don't show again" memory.
///
/// Contract (capability_matrix §6):
///  - Only recoverable warnings may pass a [warningId]; destructive or
///    irreversible confirmations must use plain dialogs and never persist.
///  - The checkbox ships UNCHECKED by default — suppression is an explicit act.
///    A caller whose notice is genuinely one-time may pass [defaultDontAsk]
///    (used by the align editor's "save as silent" explanation) so the box
///    starts ticked; the user can always restore it from meta-settings.
///  - Once the id sits in `AppState.suppressedWarnings`, callers get `true`
///    without any UI.
///
/// [isSuppressedOverride]/[onSuppressOverride] exist for widget tests; in
/// production they stay null and AppStore backs both directions.
Future<bool> showConfirmSuppressibleDialog(
  BuildContext context, {
  required String warningId,
  required String title,
  required String message,
  String? confirmLabel,
  String? cancelLabel,
  bool destructive = false,
  bool defaultDontAsk = false,
  bool Function(String id)? isSuppressedOverride,
  void Function(String id)? onSuppressOverride,
}) async {
  final store = useAppStore();
  final suppressed = isSuppressedOverride ??
      (id) => !shouldShowWarning(store.state.suppressedWarnings, id);
  final suppress =
      onSuppressOverride ?? (id) => store.suppressWarning(id);

  if (suppressed(warningId)) return true;

  final t = getLocalizations(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => ConfirmSuppressibleDialog(
      warningId: warningId,
      title: title,
      message: message,
      confirmLabel: confirmLabel ?? t.ok,
      cancelLabel: cancelLabel ?? t.cancel,
      destructive: destructive,
      defaultDontAsk: defaultDontAsk,
      onSuppress: suppress,
    ),
  );
  return confirmed ?? false;
}

/// Informational sibling of [showConfirmSuppressibleDialog]: a single OK plus
/// the same optional "don't show again" memory.
///
/// Use it for notices that only need to be ACKNOWLEDGED (no decision to make) —
/// the vocabulary is deliberately one button, so an FYI never looks like a
/// confirm/cancel choice.
Future<void> showInfoSuppressibleDialog(
  BuildContext context, {
  required String warningId,
  required String title,
  required String message,
  bool defaultDontAsk = false,
  bool Function(String id)? isSuppressedOverride,
  void Function(String id)? onSuppressOverride,
}) async {
  final store = useAppStore();
  final suppressed = isSuppressedOverride ??
      (id) => !shouldShowWarning(store.state.suppressedWarnings, id);
  final suppress =
      onSuppressOverride ?? (id) => store.suppressWarning(id);

  if (suppressed(warningId)) return;

  await showDialog<void>(
    context: context,
    builder: (_) => _InfoSuppressibleDialog(
      warningId: warningId,
      title: title,
      message: message,
      defaultDontAsk: defaultDontAsk,
      onSuppress: suppress,
    ),
  );
}

class _InfoSuppressibleDialog extends StatefulWidget {
  const _InfoSuppressibleDialog({
    required this.warningId,
    required this.title,
    required this.message,
    required this.onSuppress,
    this.defaultDontAsk = false,
  });

  final String warningId;
  final String title;
  final String message;
  final void Function(String id) onSuppress;
  final bool defaultDontAsk;

  @override
  State<_InfoSuppressibleDialog> createState() =>
      _InfoSuppressibleDialogState();
}

class _InfoSuppressibleDialogState extends State<_InfoSuppressibleDialog> {
  late bool _dontAskAgain = widget.defaultDontAsk;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    return AlertDialog(
      icon: const Icon(Icons.music_note_rounded),
      title: Text(widget.title),
      // Scrollable so a long explainer (multi-paragraph feature tours) never
      // overflows on short/landscape viewports.
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.message),
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
      actions: [
        FilledButton(
          onPressed: () {
            if (_dontAskAgain) widget.onSuppress(widget.warningId);
            Navigator.of(context).pop();
          },
          child: Text(t.ok),
        ),
      ],
    );
  }
}

class ConfirmSuppressibleDialog extends StatefulWidget {
  const ConfirmSuppressibleDialog({
    super.key,
    required this.warningId,
    required this.title,
    required this.message,
    required this.onSuppress,
    required this.confirmLabel,
    required this.cancelLabel,
    this.destructive = false,
    this.defaultDontAsk = false,
  });

  final String warningId;
  final String title;
  final String message;
  final void Function(String id) onSuppress;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;
  final bool defaultDontAsk;

  @override
  State<ConfirmSuppressibleDialog> createState() =>
      _ConfirmSuppressibleDialogState();
}

class _ConfirmSuppressibleDialogState extends State<ConfirmSuppressibleDialog> {
  late bool _dontAskAgain = widget.defaultDontAsk;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final t = getLocalizations(context);
    return AlertDialog(
      icon: widget.destructive
          ? Icon(Icons.warning_amber_rounded, color: colorScheme.error)
          : const Icon(Icons.warning_amber_rounded),
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.message),
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
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          style: widget.destructive
              ? FilledButton.styleFrom(
                  backgroundColor: colorScheme.error,
                  foregroundColor: colorScheme.onError,
                )
              : null,
          onPressed: () {
            if (_dontAskAgain) widget.onSuppress(widget.warningId);
            Navigator.of(context).pop(true);
          },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
