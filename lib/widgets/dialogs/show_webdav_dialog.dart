import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/features/meta_settings/meta_settings_module.dart';
import 'package:iris/features/webdav_discovery/legacy/legacy_webdav_scan.dart';
import 'package:iris/features/webdav_discovery/model/discovery_models.dart';
import 'package:iris/features/webdav_discovery/services/webdav_discovery.dart';
import 'package:iris/features/webdav_discovery/services/webdav_group.dart';
import 'package:iris/models/enums/storage_list_error.dart';
import 'package:iris/models/enums/webdav_scan_mode.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/models/storages/storage_name_composer.dart';
import 'package:iris/models/storages/storage_name_prefs.dart';
import 'package:iris/models/storages/webdav.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_storage_store.dart';
import 'package:iris/store/warning_dialogs.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/adaptive/ime_focus_reshow.dart';
import 'package:iris/widgets/adaptive/keyboard_form_shell.dart';
import 'package:iris/widgets/dialogs/show_confirm_suppressible_dialog.dart';
import 'package:iris/widgets/dialogs/storage_name_template_section.dart';
import 'package:iris/widgets/dialogs/storage_scope_link.dart';
import 'package:uuid/uuid.dart';

/*
Host resolution has two strategy-selected paths (AppState.webDavScanMode):
  • discovery  — cached hosts → SSDP → subnet-aware bounded-concurrency scan
  • legacyScan — the original serial isolate scan (preserved verbatim)
*/

Future<void> showWebDAVDialog(BuildContext context, {WebDAVStorage? storage}) =>
    showAdaptiveKeyboardForm<void>(
      context: context,
      form: WebDavForm(
        storage: storage,
        // Sheet shell on phones, dialog shell on desktop (see the shell).
        fillViewport: isKeyboardFormSheet(context),
      ),
    );

/// WebDAV add/edit form.
///
/// Keyboard-safe shell: the heavy form is built once by
/// [showAdaptiveKeyboardForm] and never reads `MediaQuery`, so keyboard frames
/// only repad it. Behaviour (test-before-save, discovery/legacy scan, password
/// semantics) is unchanged from the previous `AlertDialog` version.
class WebDavForm extends HookWidget {
  const WebDavForm({super.key, this.storage, this.fillViewport = false});

  final WebDAVStorage? storage;

  /// True inside the bottom-sheet shell (fill the sheet).
  final bool fillViewport;

  /// Test seam: counts form builds to prove keyboard frames don't re-run the
  /// form. Null in prod.
  static void Function()? debugOnFormBuild;

  @override
  Widget build(BuildContext context) {
    debugOnFormBuild?.call();
    final t = getLocalizations(context);
    final appStore = useAppStore();
    final storageStore = useStorageStore();
    final bool isEdit = storage != null && (storageStore.state.storages.contains(storage));
    final showHostHint = useState(false);

    final subscription = useRef<StreamSubscription<Object?>?>(null);

    final progressIndex = useState<int>(0);
    final progressTotal = useState<int>(0);

    final id = useMemoized(() => storage?.id ?? const Uuid().v4());
    // Text lives in controllers, NOT `useState`: writing hook state on every
    // keystroke rebuilt the entire form (all fields + template preview). Only
    // the small subtrees that must react live subscribe to these controllers.
    final nameCtrl = useTextEditingController(text: storage?.name ?? '');
    final hostCtrl = useTextEditingController(text: storage?.host ?? '');
    final basePath = useState(storage?.basePath ?? ['/']);
    final usernameCtrl = useTextEditingController(text: storage?.username ?? '');
    // Saved password is never displayed, even as obscured dots. Edit mode
    // starts with an empty field; empty means "keep the saved password".
    // trim() explicitly strips leading/trailing whitespace — intentional.
    final String savedPassword = useMemoized(() => storage?.password ?? '', [storage]);
    final passwordCtrl = useTextEditingController();
    final obscurePassword = useState(true);
    final https = useState(storage?.https ?? false);
    final resolvedHosts = useState<List<String>>(storage?.resolvedHosts ?? const <String>[]);

    /// Host as typed, normalized the way it is persisted (`//host` and
    /// surrounding spaces are stripped at read time instead of per keystroke).
    String currentHost() => hostCtrl.text.trim().split('//').last;

    String effectivePassword() => isEdit && passwordCtrl.text.isEmpty
        ? savedPassword
        : passwordCtrl.text.trim();

    // A plain notifier (not hook state): flipping "tested → false" on every
    // keystroke must not rebuild the form. The two spots that render it
    // (Save enablement, retry-with-saved-password row) subscribe explicitly.
    final isTested = useMemoized(() => ValueNotifier<bool>(false));
    useEffect(() => isTested.dispose, const []);
    final isTesting = useState(false);

    final TextEditingController portController =
        useTextEditingController(text: storage?.port ?? '');
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
            typeLabel: 'WebDAV',
            username: usernameCtrl.text.trim(),
            host: currentHost(),
            port: portController.text,
            isDefaultPort: isDefaultWebDavPort(portController.text, https.value),
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

    WebDAVStorage buildStorage({String? hostOverride}) => WebDAVStorage(
          id: id,
          name: resolvedName(),
          host: hostOverride ?? currentHost(),
          resolvedHosts: resolvedHosts.value,
          basePath: basePath.value,
          port: portController.text,
          username: usernameCtrl.text.trim(),
          password: effectivePassword(),
          https: https.value,
          // Preserve the current data-scope link across the rebuild; an edit
          // must not silently detach the entry from its shared library.
          dataScopeId: storage?.dataScopeId,
        );

    List<String> withHost(String value) => <String>[
          value,
          ...resolvedHosts.value.where((h) => h != value),
        ];

    void add(WebDAVStorage resolved) {
      storageStore.addStorage(resolved);
    }

    void update(WebDAVStorage resolved) {
      storageStore.updateStorage(
        storageStore.state.storages.indexOf(storage as Storage),
        resolved,
      );
    }

    /// Resolves the data-scope link (shared library) before saving. Returns
    /// null when a NEW entry's "same tree" prompt is cancelled (abort); in edit
    /// mode a cancelled prompt keeps the original link instead.
    Future<WebDAVStorage?> resolveLink() async {
      final linked = await resolveSharedLibraryLink(
        context,
        buildStorage(),
        storageStore.state.storages,
        isEdit: isEdit,
        originalScopeId: storage?.dataScopeId,
      );
      return linked is WebDAVStorage ? linked : null;
    }

    final testingIp = useState<String?>(null);
    final testResult = useState<String?>(null);

    // Declared `late` so the exhaustion handler can re-run the scan without a
    // forward-reference error (mutual local closures).
    late void Function(WebDAVStorage target, {bool ignoreExclusions})
        runDiscoveryScan;

    /// Nothing new resolved, but independent sibling entries claimed hosts.
    /// Ask (suppressibly) whether this entry may share one, then retry without
    /// exclusions. Declining keeps the original explanatory message.
    void handleDiscoveryExhausted(WebDAVStorage target, Set<String> excluded) {
      if (excluded.isEmpty) {
        testResult.value = t.connection_failed;
        isTesting.value = false;
        return;
      }
      final blocked = excluded.toList();
      final ctx = context;
      isTesting.value = false;
      unawaited(() async {
        final allowed = await showConfirmSuppressibleDialog(
          ctx,
          warningId: kWarningWebdavSharedHost,
          title: t.webdav_shared_host_confirm_title,
          message: t.webdav_shared_host_confirm_message(blocked.first),
        );
        if (!ctx.mounted) return;
        if (allowed) {
          isTesting.value = true;
          testResult.value = null;
          runDiscoveryScan(target, ignoreExclusions: true);
        } else {
          testResult.value = t.webdav_no_distinct_host(blocked.first);
        }
      }());
    }

    runDiscoveryScan = (WebDAVStorage target, {bool ignoreExclusions = false}) {
      // A linked sibling (shared data scope) never blocks; only independent
      // same-account entries claim hosts. When the user overrides the claim we
      // re-run with no exclusions.
      final excluded = ignoreExclusions
          ? const <String>{}
          : claimedBySiblings(target, storageStore.state.storages);
      subscription.value = WebDavDiscovery()
          .resolve(target, excludedHosts: excluded)
          .listen(
        (event) {
          switch (event) {
            case DiscoveryCandidate(:final host, :final index, :final total):
              testingIp.value = host;
              progressIndex.value = index;
              progressTotal.value = total;
            // Informational only: the resolver already picked deterministically
            // and logs the ambiguity. Emitted before DiscoveryVerified.
            case DiscoveryAmbiguous():
              break;
            case DiscoveryVerified(:final host):
              resolvedHosts.value = withHost(host);
              isTested.value = true;
              testResult.value = '${t.connected_to} $host';
              isTesting.value = false;
              subscription.value?.cancel();
              subscription.value = null;
            case DiscoveryAuthRejected():
              testResult.value = t.webdav_auth_rejected;
              isTesting.value = false;
            case DiscoveryExhausted():
              handleDiscoveryExhausted(target, excluded);
          }
        },
        onError: (Object _) {
          testResult.value = t.connection_failed;
          isTesting.value = false;
        },
      );
    };

    void runLegacyScan(WebDAVStorage target) {
      late List<String> hosts;
      try {
        hosts = expandIPv4Wildcard(target.host);
      } on FormatException {
        testResult.value = t.invalid_ip_pattern;
        isTesting.value = false;
        return;
      }
      progressTotal.value = hosts.length;
      progressIndex.value = 0;

      subscription.value = const LegacyWebDavScanner().scan(target, hosts).listen(
        (event) {
          switch (event) {
            case LegacyScanCandidate(:final host, :final index, :final total):
              testingIp.value = host;
              progressIndex.value = index;
              progressTotal.value = total;
            case LegacyScanVerified(:final host):
              resolvedHosts.value = withHost(host);
              isTested.value = true;
              testResult.value = '${t.connected_to} $host';
              isTesting.value = false;
              subscription.value?.cancel();
              subscription.value = null;
            case LegacyScanExhausted():
              testResult.value = t.connection_failed;
              isTesting.value = false;
          }
        },
        onError: (Object _) {
          testResult.value = t.connection_failed;
          isTesting.value = false;
        },
      );
    }

    void testConnection() async {
      if (isTesting.value) {
        await subscription.value?.cancel();
        subscription.value = null;
        isTesting.value = false;
        testResult.value = t.test_cancelled;
        return;
      }
      isTesting.value = true;
      isTested.value = false;
      testingIp.value = null;
      progressIndex.value = 0;
      progressTotal.value = 0;
      testResult.value = null;

      final rawHost = currentHost();

      // Case 1: IPv4 wildcard → strategy-selected scan.
      if (isIPv4WildcardHost(rawHost)) {
        final target = buildStorage();
        if (appStore.state.webDavScanMode == WebDavScanMode.legacyScan) {
          runLegacyScan(target);
        } else {
          runDiscoveryScan(target);
        }
        return;
      }

      // Case 2: normal single-host test (hostname, IPv4, IPv6, etc.).
      // Prefer a cached resolution over the host as typed. Failures keep
      // their classification (unreachable vs rejected credentials) instead
      // of collapsing into a generic "connection failed".
      final cachedHost = resolvedHosts.value.isEmpty ? null : resolvedHosts.value.first;
      final result = await getWebDAVFilesResult(
        buildStorage(hostOverride: cachedHost ?? rawHost),
        basePath.value,
      );

      isTested.value = !result.hasError;
      if (!result.hasError) {
        testResult.value = t.connected_to;
      } else {
        testResult.value = switch (result.errorKind) {
          StorageListErrorKind.unreachable => t.browser_error_unreachable,
          StorageListErrorKind.unauthorized => t.browser_error_unauthorized,
          StorageListErrorKind.timeout => t.browser_error_timeout,
          StorageListErrorKind.httpBlocked => t.browser_error_http_blocked,
          _ => t.connection_failed,
        };
      }
      isTesting.value = false;
    }

    useEffect(() {
      return () {
        subscription.value?.cancel();
        subscription.value = null;
      };
    }, const []);

    return KeyboardFormScaffold(
      fillViewport: fillViewport,
      title: Text(isEdit ? t.edit_webdav_storage : t.add_webdav_storage),
      onClose: () async {
        await subscription.value?.cancel();
        subscription.value = null;
        if (context.mounted) Navigator.of(context).pop('Cancel');
      },
      body: Form(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The name hint + template preview derive from host / username /
            // port / separator; a scoped listener keeps them live while typing
            // those fields WITHOUT rebuilding the rest of the form.
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
            if (testingIp.value != null || testResult.value != null) ...[
              const SizedBox(height: 8),
              if (testingIp.value != null)
                Text(
                  t.webdav_testing_host(
                    testingIp.value!,
                    progressIndex.value,
                    progressTotal.value,
                  ),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              if (testResult.value != null)
                Text(
                  testResult.value!,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.primary),
                ),
            ],
            const SizedBox(height: 6),
            InkWell(
              onTap: () => showHostHint.value = !showHostHint.value,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      showHostHint.value ? Icons.expand_less : Icons.info_outline,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        t.host_hint_toggle, // new ARB key
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  t.webdav_host_hint,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
              crossFadeState:
                  showHostHint.value ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
            const SizedBox(height: 16.0),
            TextFormField(
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: t.path,
                ),
                initialValue: basePath.value.join('/'),
                onChanged: (value) {
                  final trimmedValue = value.trim().replaceAll(RegExp(r'^\/+|\/+$'), '');
                  final finalPath = '/$trimmedValue';
                  basePath.value = [finalPath];
                  isTested.value = false;
                }),
            const SizedBox(height: 16.0),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
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
                      if (value == '443') {
                        https.value = true;
                      }
                    },
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () {
                    isTested.value = false;
                    if (!https.value) {
                      portController.text = '443';
                    } else {
                      portController.text = '80';
                    }
                    https.value = !https.value;
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Flexible(
                          child: Text('https', overflow: TextOverflow.ellipsis),
                        ),
                        Focus(
                          descendantsAreFocusable: false,
                          canRequestFocus: false,
                          child: Checkbox(
                            value: https.value,
                            onChanged: (_) {
                              isTested.value = false;
                              if (portController.text == '80' && https.value == false) {
                                portController.text = '443';
                              } else if (portController.text == '443' &&
                                  https.value == true) {
                                portController.text = '80';
                              }
                              https.value = !https.value;
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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
              key: ValueKey('webdav-password-${isEdit ? 'edit' : 'add'}-${obscurePassword.value}'),
              controller: passwordCtrl,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: t.password,
                // Saved password is never displayed; empty = keep saved.
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
            // Rebuilds only when the password text or test outcome changes, not
            // on every keystroke of unrelated fields.
            ListenableBuilder(
              listenable: Listenable.merge(<Listenable>[isTested, passwordCtrl]),
              builder: (context, _) {
                final failed = testResult.value != null &&
                    testResult.value != t.connected_to;
                if (!isEdit ||
                    isTested.value ||
                    !failed ||
                    passwordCtrl.text.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      // Abandon the new password input and retry with the last
                      // successful (saved) password. Never reveals the saved
                      // password value — only uses it for the connection test.
                      passwordCtrl.clear();
                      isTested.value = false;
                      testResult.value = null;
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
            onPressed: () async {
              await subscription.value?.cancel();
              subscription.value = null;
              if (context.mounted) Navigator.pop(context, 'Cancel');
            },
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: testConnection,
            child: Text(isTesting.value ? t.cancel_test : t.test_connection),
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
