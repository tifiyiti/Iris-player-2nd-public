import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/models/storages/volume_identity.dart';
import 'package:iris/store/use_storage_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/path_conv.dart';
import 'package:iris/utils/platform.dart';
import 'package:iris/widgets/adaptive/keyboard_form_shell.dart';
import 'package:iris/widgets/popups/storages/db/storages_utils/storage_utils.dart';
import 'package:path/path.dart' as p;

/// Add/edit local-folder form, routed through the canonical keyboard shell so
/// keyboard frames only repad a cached form (see [KeyboardFormScaffold]).
Future<void> showFolderDialog(BuildContext context,
        {LocalStorage? storage}) =>
    showAdaptiveKeyboardForm<void>(
      context: context,
      form: LocalForm(
        storage: storage,
        // Sheet shell on phones, dialog shell on desktop.
        fillViewport: isKeyboardFormSheet(context),
      ),
    );

class LocalForm extends HookWidget {
  const LocalForm({
    super.key,
    this.storage,
    this.fillViewport = false,
  });
  final LocalStorage? storage;

  /// True inside the bottom-sheet shell (fill the sheet).
  final bool fillViewport;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final bool isEdit = storage != null &&
        (useStorageStore().state.storages.contains(storage!));
    final type = useState(storage?.type ?? StorageType.internal);
    final name = useState(storage?.name ?? '');
    final basePath = useState(storage?.basePath ?? []);

    final isTested = useState(true);

    Future<void> add() async {
      // Resolve the stable volume identity so a manually added folder keeps the
      // same id/scope when its drive letter changes (see VolumeIdentity).
      final volumeId = await VolumeIdentity.of(basePath.value.join('/'));
      await useStorageStore().addStorage(
        makeLocalStorage(
          type: type.value,
          name: name.value,
          basePath: basePath.value,
          volumeId: volumeId,
        ),
      );
    }

    Future<void> update() async {
      final volumeId = await VolumeIdentity.of(basePath.value.join('/'));
      final updated = makeLocalStorage(
        type: type.value,
        name: name.value,
        basePath: basePath.value,
        volumeId: volumeId,
      ).copyWith(id: storage!.id);
      await useStorageStore().updateStorage(
        useStorageStore().state.storages.indexOf(storage! as Storage),
        updated,
      );
    }

    return KeyboardFormScaffold(
      fillViewport: fillViewport,
      title: Text(isEdit ? t.edit_folder : t.add_folder),
      onClose: () => Navigator.pop(context, 'Cancel'),
      body: Form(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: t.name,
              ),
              initialValue: name.value,
              onChanged: (value) => name.value = value.trim(),
            ),
            const SizedBox(height: 16.0),
            TextFormField(
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: t.path,
              ),
              initialValue: p.normalize(basePath.value.join('/')),
              onChanged: (value) => basePath.value = pathConv(value),
              readOnly:
                  isAndroid && basePath.value[0].startsWith('content://'),
            ),
            const SizedBox(height: 16.0),
          ],
        ),
      ),
      footer: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'Cancel'),
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: isTested.value
                ? () {
                    Navigator.pop(context, 'OK');
                    isEdit ? update() : add();
                  }
                : null,
            child: Text(isEdit ? t.save : t.add),
          ),
        ],
      ),
    );
  }
}
