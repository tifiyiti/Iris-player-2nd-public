import 'package:flutter/material.dart';
import 'package:iris/store/warning_dialogs.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/dialogs/show_confirm_suppressible_dialog.dart';

/// Asks the user whether to force-add an otherwise unplayable selection to the
/// workspace (D14). Returns true on confirm (the caller then skips the
/// playability pre-check with `force`), false on cancel (state unchanged).
///
/// [confirmLabel] overrides the confirm button text (D29: append flows use
/// a force-append label; override flows keep the default).
///
/// Suppressible (capability_matrix §6, id A2): the result is reversible, so
/// after "don't show again" this auto-confirms without UI.
Future<bool> showNoMediaConfirmDialog(
  BuildContext context, {
  String? confirmLabel,
}) {
  final t = getLocalizations(context);
  return showConfirmSuppressibleDialog(
    context,
    warningId: kWarningForceAppendNoMedia,
    title: t.dlg_no_media_title,
    message: t.dlg_no_media_message,
    confirmLabel: confirmLabel ?? t.dlg_no_media_confirm,
  );
}
