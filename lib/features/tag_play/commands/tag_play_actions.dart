import 'package:flutter/material.dart';
import 'package:iris/features/tag_play/playback/tag_play_controller.dart';
import 'package:iris/features/tag_play/view/tag_play_sheet.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/warning_dialogs.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/dialogs/show_confirm_suppressible_dialog.dart';
import 'package:iris/widgets/dialogs/show_message_dialog.dart';
import 'package:iris/widgets/popup.dart';

/// Single entry point shared by every trigger: one feature, several doors.
///
/// [initialCommand] prefills the numeric command bar — the Windows numpad
/// entry keys pass their operator (`+`/`-`/`*`) so the user only types the
/// ordinals; the region-gesture and more-menu doors leave it null.
///
/// Fully bound to the metadata-driven era: when the gate is OFF the feature
/// does not exist — the entry explains why instead of silently doing nothing
/// (project rule: feedback via Dialog, never SnackBar).
Future<void> openTagPlaySheet(
  BuildContext context, {
  String? initialCommand,

  /// When true (default) show the first-use numeric-command explainer before
  /// the sheet opens. Tests pass false to skip the modal.
  bool showCommandGuide = true,
}) async {
  if (!TagPlayGate.enabled) {
    final navigator = Navigator.of(context, rootNavigator: true);
    await showMessageDialog(
      navigator,
      message: getLocalizations(context).tag_gate_meta_body,
      type: MessageDialogType.info,
    );
    return;
  }
  if (showCommandGuide) {
    final t = getLocalizations(context);
    await showInfoSuppressibleDialog(
      context,
      warningId: kWarningTagCommandGrammar,
      title: t.dlg_warn_tag_grammar_title,
      message: t.dlg_tag_grammar_body,
      defaultDontAsk: true,
    );
    if (!context.mounted) return;
  }
  final direction = useAppStore().state.defaultPopupDirection;
  await showPopup(
    context: context,
    child: TagPlaySheet(
      initialCommand: initialCommand,
      // Only the shortcut door prefills an operator; it is the one door the
      // "close after a command" opt-in applies to.
      openViaShortcut: initialCommand != null,
    ),
    direction: direction,
  );
}
