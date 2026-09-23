import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/features/meta_settings/meta_settings_module.dart';
import 'package:iris/models/storages/ftp.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/models/storages/storage_name_composer.dart';
import 'package:iris/models/storages/storage_name_prefs.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_storage_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/adaptive/ime_focus_reshow.dart';
import 'package:iris/widgets/adaptive/keyboard_form_shell.dart';
import 'package:iris/widgets/dialogs/storage_name_template_section.dart';
import 'package:iris/widgets/dialogs/storage_scope_link.dart';
import 'package:uuid/uuid.dart';

Future<void> showFTPDialog(BuildContext context, {FTPStorage? storage}) =>
    showAdaptiveKeyboardForm<void>(
      context: context,
      form: FtpForm(
        storage: storage,
        fillViewport: isKeyboardFormSheet(context),
      ),
    );

/// FTP add/edit form.
///
/// Keyboard-safe shell: built once by [showAdaptiveKeyboardForm], reads no
/// `MediaQuery`, so keyboard frames only repad it. Behaviour (test-before-save,
/// password semantics) is unchanged from the previous `AlertDialog` version.
class FtpForm extends HookWidget {
  const FtpForm({super.key, this.storage, this.fillViewport = false});

  final FTPStorage? storage;

  /// True inside the bottom-sheet shell (fill the sheet).
  final bool fillViewport;

  /// Test seam: counts form builds to prove keyboard frames don't re-run the
  /// form. Null in prod.
  static void Function()? debugOnFormBuild;

  @override
  Widget build(BuildContext context) {
    debugOnFormBuild?.call();
    final t = getLocalizations(context);
    final storageStore = useStorageStore();
    final appStore = useAppStore();
    final bool isEdit =
        storage != null && (storageStore.state.storages.contains(storage));

    final id = useMemoized(() => storage?.id ?? const Uuid().v4());
    // Text lives in controllers, NOT `useState`: writing hook state on every
    // keystroke rebuilt the entire form. Only the small subtrees that must
    // react live subscribe to these controllers.
    final nameCtrl = useTextEditingController(text: storage?.name ?? '');
    final hostCtrl = useTextEditingController(text: storage?.host ?? '');
    final basePath = useState(storage?.basePath ?? ['/']);
    final usernameCtrl = useTextEditingController(text: storage?.username ?? '');
    // Saved password is never displayed, even as dots. Edit mode starts
    // empty; empty means "keep saved password". trim() explicitly strips
    // leading/trailing whitespace — intentional.
    final String savedPassword = useMemoized(() => storage?.password ?? '', [storage]);
    final passwordCtrl = useTextEditingController();
    final obscurePassword = useState(true);

    /// Host as typed, normalized the way it is persisted.
    String currentHost() => hostCtrl.text.trim().split('//').last;

    String effectivePassword() => isEdit && passwordCtrl.text.isEmpty
        ? savedPassword
        : passwordCtrl.text.trim();

    // A plain notifier (not hook state): flipping "tested → false" on every
    // keystroke must not rebuild the form. Save enablement subscribes to it.
    final isTested = useMemoized(() => ValueNotifier<bool>(false));
    useEffect(() => isTested.dispose, const []);

    final TextEditingController portController =
        useTextEditingController(text: storage?.port ?? '21');
    // HyperOS secure-keyboard replay on every field-to-field focus change
    // (both password→normal and normal→password), #166311.
    useImeReshowOnFocusChange();

    // Storage-name template: entirely absent in legacy / gate-OFF mode.
    final bool showTemplate =
        MetaSettingsModule.ready && appStore.state.useMetadataSettings;
    final templateTags =
        useState<List<StorageNameTag>>(StorageNamePrefs.template.tags);
    final templateGlobal = useState<bool>(StorageNamePrefs.template.enabled);
    final separatorController =
        useTextEditingController(text: StorageNamePrefs.template.separator);

    List<StorageNameEntry> nameEntries() => storageStore.state.storages
        .map((s) => (id: s.id, name: s.name))
        .toList(growable: false);

    String templateDefaultName() => uniqueStorageName(
          composeStorageName(
            tags: templateTags.value,
            separator: separatorController.text,
            typeLabel: 'FTP',
            username: usernameCtrl.text.trim(),
            host: currentHost(),
            port: portController.text,
            isDefaultPort: isDefaultFtpPort(portController.text),
            pathLast: storageNameLastPathSegment(basePath.value),
          ),
          nameEntries(),
          excludeId: storage?.id,
        );

    String resolvedName() {
      if (!showTemplate) return nameCtrl.text.trim();
      final typed = nameCtrl.text.trim();
      if (typed.isEmpty) return templateDefaultName();
      return uniqueStorageName(typed, nameEntries(), excludeId: storage?.id);
    }

    FTPStorage buildStorage() => FTPStorage(
          id: id,
          name: resolvedName(),
          host: currentHost(),
          basePath: basePath.value,
          port: portController.text,
          username: usernameCtrl.text.trim(),
          password: effectivePassword(),
          // Preserve the current data-scope link across the rebuild.
          dataScopeId: storage?.dataScopeId,
        );

    void add(FTPStorage resolved) {
      storageStore.addStorage(resolved);
    }

    void update(FTPStorage resolved) {
      storageStore.updateStorage(
        storageStore.state.storages.indexOf(storage as Storage),
        resolved,
      );
    }

    /// Resolves the data-scope link (shared library) before saving. Returns
    /// null when a NEW entry's "same tree" prompt is cancelled (abort); in edit
    /// mode a cancelled prompt keeps the original link instead.
    Future<FTPStorage?> resolveLink() async {
      final linked = await resolveSharedLibraryLink(
        context,
        buildStorage(),
        storageStore.state.storages,
        isEdit: isEdit,
        originalScopeId: storage?.dataScopeId,
      );
      return linked is FTPStorage ? linked : null;
    }

    void testConnection() async {
      final bool isConnected = await testFTP(FTPStorage(
        id: id,
        name: resolvedName(),
        host: currentHost(),
        basePath: basePath.value,
        port: portController.text,
        username: usernameCtrl.text.trim(),
        password: effectivePassword(),
      ));
      isTested.value = isConnected;
    }

    return KeyboardFormScaffold(
      fillViewport: fillViewport,
      title: Text(isEdit ? t.edit_ftp_storage : t.add_ftp_storage),
      onClose: () => Navigator.pop(context, 'Cancel'),
      body: Form(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Name hint + template preview derive from host/username/port/
            // separator; a scoped listener keeps them live without rebuilding
            // the rest of the form on every keystroke.
            ListenableBuilder(
              listenable: Listenable.merge(<Listenable>[
                hostCtrl,
                usernameCtrl,
                portController,
                separatorController,
              ]),
              builder: (context, _) {
                final String? templateDefault =
                    showTemplate ? templateDefaultName() : null;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: t.name,
                        floatingLabelBehavior: showTemplate
                            ? FloatingLabelBehavior.always
                            : null,
                        hintText: templateDefault,
                      ),
                      onChanged: (_) => isTested.value = false,
                    ),
                    if (showTemplate) ...[
                      const SizedBox(height: 12),
                      StorageNameTemplateSection(
                        tags: templateTags.value,
                        separatorController: separatorController,
                        global: templateGlobal.value,
                        previewName: templateDefault ?? '',
                        onToggleTag: (tag) {
                          final next = <StorageNameTag>[...templateTags.value];
                          if (!next.remove(tag)) next.add(tag);
                          templateTags.value = next;
                          StorageNamePrefs.updateTags(next);
                        },
                        onSeparatorChanged: StorageNamePrefs.applySeparator,
                        onSeparatorCommitted: StorageNamePrefs.commitSeparator,
                        onGlobalChanged: (value) {
                          templateGlobal.value = value;
                          StorageNamePrefs.updateEnabled(value);
                        },
                        onReset: () {
                          templateTags.value = StorageNameTemplate.defaultTags;
                          separatorController.text =
                              StorageNameTemplate.defaultSeparator;
                          StorageNamePrefs.reset();
                        },
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 16.0),
            TextFormField(
              controller: hostCtrl,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: t.host,
              ),
              // Sanitized at read time (`currentHost`), not per keystroke.
              onChanged: (_) => isTested.value = false,
            ),
            const SizedBox(height: 16.0),
            TextFormField(
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: t.path,
                ),
                initialValue: basePath.value.join('/'),
                onChanged: (value) {
                  final trimmedValue =
                      value.trim().replaceAll(RegExp(r'^\/+|\/+$'), '');
                  final finalPath = '/$trimmedValue';
                  basePath.value = [finalPath];
                  isTested.value = false;
                }),
            const SizedBox(height: 16.0),
            TextFormField(
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: t.port,
              ),
              controller: portController,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              onChanged: (value) {
                isTested.value = false;
              },
            ),
            const SizedBox(height: 16.0),
            TextFormField(
              controller: usernameCtrl,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: t.username,
              ),
              onChanged: (_) => isTested.value = false,
            ),
            const SizedBox(height: 16.0),
            TextFormField(
              key: ValueKey('ftp-password-${isEdit ? 'edit' : 'add'}-${obscurePassword.value}'),
              controller: passwordCtrl,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: t.password,
                hintText: isEdit ? t.storage_keep_saved_password_hint : null,
                suffixIcon: IconButton(
                  icon: Icon(
                    obscurePassword.value ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () => obscurePassword.value = !obscurePassword.value,
                ),
              ),
              obscureText: obscurePassword.value,
              enableInteractiveSelection: true,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (_) => isTested.value = false,
            ),
            ListenableBuilder(
              listenable:
                  Listenable.merge(<Listenable>[isTested, passwordCtrl]),
              builder: (context, _) {
                if (!isEdit ||
                    isTested.value ||
                    passwordCtrl.text.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      // Abandon new input, retry with last successful (saved) password.
                      passwordCtrl.clear();
                      isTested.value = false;
                      testConnection();
                    },
                    child: Text(t.dlg_retry_saved_password),
                  ),
                );
              },
            ),
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
            onPressed: testConnection,
            child: Text(t.test_connection),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: isTested,
            builder: (context, tested, _) => TextButton(
              onPressed: tested
                  ? () async {
                      // Flush a separator typed but never blurred.
                      if (showTemplate) StorageNamePrefs.commitSeparator();
                      final resolved = await resolveLink();
                      if (resolved == null || !context.mounted) return;
                      Navigator.pop(context, 'OK');
                      isEdit ? update(resolved) : add(resolved);
                    }
                  : null,
              child: Text(isEdit ? t.save : t.add),
            ),
          ),
        ],
      ),
    );
  }
}
