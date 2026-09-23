import 'package:flutter/material.dart';
import 'package:iris/features/media_library/view/tab/store/libs/use_media_libs_page_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/adaptive/keyboard_form_shell.dart';

Future<void> showCreateLibraryDialog(
  BuildContext context,
) async {
  final t = getLocalizations(context);
  final result = await showKeyboardTextPrompt(
    context: context,
    title: t.lib_create_library,
    hint: t.lib_name_hint,
    confirmLabel: t.scn_create,
    cancelLabel: t.cancel,
  );

  if (result == null || result.isEmpty) {
    return;
  }

  final store = useMediaLibsStore();
  await store.createUserLibrary(result);
}
