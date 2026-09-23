import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/app_identity/model/domain/app_identity_entry.dart';
import 'package:iris/features/app_identity/services/app_identity_facade.dart';
import 'package:iris/features/app_identity/services/app_identity_paths.dart';
import 'package:iris/features/app_identity/services/app_identity_validation.dart';
import 'package:iris/features/app_identity/services/shortcut_channel_service.dart';
import 'package:iris/features/app_identity/store/use_app_identity_store.dart';
import 'package:iris/features/app_identity/view/entry_image_cropper.dart';
import 'package:iris/features/scenario_playback/model/enum/scenario_kind.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';
import 'package:iris/features/tag_play/model/domain/tag_play_tag.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/adaptive/keyboard_form_shell.dart';
import 'package:path/path.dart' as p;

export 'app_identity_manager_page.dart' show showAppIdentityManager;

/// Square image preview resolved from documents dir; falls back to a generic
/// glyph when no custom image is set or the file is missing.
///
/// Shared by the manager page ([app_identity_manager_page.dart]) and the
/// editor dialog below.
class EntryAvatar extends StatelessWidget {
  const EntryAvatar({
    super.key,
    required this.imageRef,
    required this.size,
    this.sourcePath = '',
  });

  final String imageRef;
  final double size;
  final String sourcePath;

  @override
  Widget build(BuildContext context) {
    if (imageRef.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.movie_filter_outlined, size: size * 0.55),
      );
    }
    final file = File(AppIdentityPaths.filePath(imageRef));
    final sourceMissing = sourcePath.isNotEmpty &&
        !File(AppIdentityPaths.filePath(sourcePath)).existsSync();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.25),
          child: Image.file(
            file,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: size,
              height: size,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Icon(Icons.broken_image_outlined, size: size * 0.5),
            ),
          ),
        ),
        if (sourceMissing)
          Positioned(
            right: -4,
            top: -4,
            child: Icon(
              Icons.warning_amber_rounded,
              size: 14,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
      ],
    );
  }
}

/// Reads a prepared icon's PNG bytes from documents dir; null when absent.
abstract final class AppIdentityImageFile {
  static Future<Uint8List?> readIconPng(String imageRef) async {
    if (imageRef.isEmpty) return null;
    final f = File(AppIdentityPaths.filePath(imageRef));
    if (!await f.exists()) return null;
    try {
      return await f.readAsBytes();
    } catch (_) {
      return null;
    }
  }
}

// ── Editor ──

/// Opens the create/edit form. [existing] null = create mode.
///
/// Routed through the canonical keyboard shell ([showAdaptiveKeyboardForm]):
/// phones (<600px) get a scroll-controlled bottom sheet, wider screens a
/// centered dialog — both holding ONE cached form, so keyboard frames only
/// repad and never rebuild a field; see [KeyboardFormScaffold]. The name
/// TextField has NO `onChanged` rebuild hook, keeping CJK (composition) input
/// smooth.
///
/// Swipe-down and scrim-tap dismissal are disabled and no close button is
/// rendered: the form holds unsaved input, so only the footer Cancel button
/// may discard it.
Future<void> openAppIdentityEditor(
  BuildContext context, {
  AppIdentityEntry? existing,
}) {
  return showAdaptiveKeyboardForm<void>(
    context: context,
    enableDrag: false,
    isDismissible: false,
    showDragHandle: false,
    form: EntryEditorForm(
      existing: existing,
      fillViewport: isKeyboardFormSheet(context),
    ),
  );
}

/// Shared editor form built on [KeyboardFormScaffold] (sticky title header /
/// scrollable fields / sticky footer). Built once per shell and reads NO
/// MediaQuery, so keyboard frames only repad it.
class EntryEditorForm extends HookWidget {
  const EntryEditorForm({super.key, this.existing, this.fillViewport = false});

  final AppIdentityEntry? existing;
  final bool fillViewport;

  /// Test seam: counts form rebuilds to prove keyboard frames don't re-run it.
  static void Function()? debugOnFormBuild;

  @override
  Widget build(BuildContext context) {
    debugOnFormBuild?.call();
    final t = getLocalizations(context);
    final navigator = Navigator.of(context);

    final nameCtrl = useTextEditingController(text: existing?.name ?? '');
    final nameNode = useFocusNode();
    final shared = useState<bool>(existing?.sharedWithDefault ?? false);
    final seedScenarioId = useState<String?>(existing?.seedScenarioId);
    final seedTagId = useState<int?>(existing?.seedTagId);
    final editResult = useState<EntryImageEditResult?>(null);
    final busy = useState(false);
    final sourceMissing = useState<bool>(_sourceMissing(existing));

    // An entry must carry an icon: either freshly picked this session or
    // inherited from the existing entry. Disk existence is intentionally NOT
    // checked here — a dangling ref stays editable, preserving the old icon.
    final hasImage =
        editResult.value != null || (existing?.imageRef.isNotEmpty ?? false);

    // Keep the focused name field visible when the keyboard opens. The chrome
    // (header + image picker) always stays mounted; scrolling happens inside
    // the scaffold's body, so this is a one-shot scroll on focus.
    useEffect(() {
      void onFocus() {
        if (!nameNode.hasFocus) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = nameNode.context;
          if (ctx != null) {
            Scrollable.ensureVisible(ctx,
                duration: const Duration(milliseconds: 200));
          }
        });
      }

      nameNode.addListener(onFocus);
      return () => nameNode.removeListener(onFocus);
    }, [nameNode]);

    final allScenarios =
        usePlaybackScenarioStore().select(context, (s) => s.scenarios);
    final scenarios =
        allScenarios.where((s) => s.type == ScenarioKind.userSaved).toList();
    final tagsSnapshot = useFuture<List<TagPlayTag>>(useMemoized(() async {
      try {
        return await DbModule.tagPlayRepo.tags();
      } catch (_) {
        return const <TagPlayTag>[];
      }
    }, const []));
    final tags = tagsSnapshot.data ?? const <TagPlayTag>[];

    // Drop seed references that no longer resolve (scenario/tag deleted since
    // binding). A dangling id would otherwise render an empty/asserting
    // dropdown and silently persist a binding that can never initialize.
    useEffect(() {
      final sid = seedScenarioId.value;
      if (sid == null || allScenarios.isEmpty) return null;
      final exists = allScenarios
          .any((s) => s.id == sid && s.type == ScenarioKind.userSaved);
      if (!exists) seedScenarioId.value = null;
      return null;
    }, [allScenarios]);

    useEffect(() {
      final tid = seedTagId.value;
      if (tid == null || !tagsSnapshot.hasData) return null;
      if (!tags.any((tag) => tag.id == tid)) seedTagId.value = null;
      return null;
    }, [tagsSnapshot.hasData, tags]);

    Future<void> pickAndCrop() async {
      busy.value = true;
      try {
        final existingSource = existing?.sourcePath ?? '';
        final sourceBytes = editResult.value?.sourceBytes ??
            (existingSource.isNotEmpty
                ? await _readSourceBytes(existingSource)
                : null);
        final cropRect = editResult.value?.cropRect ??
            (existingSource.isNotEmpty
                ? ui.Rect.fromLTRB(
                    existing?.cropLeft ?? 0,
                    existing?.cropTop ?? 0,
                    existing?.cropRight ?? 1,
                    existing?.cropBottom ?? 1,
                  )
                : null);
        final result = await showEntryImageEditor(
          navigator.context,
          initialBytes: sourceBytes,
          initialCropRect: cropRect,
        );
        if (result != null) {
          editResult.value = result;
          sourceMissing.value = false;
        }
      } finally {
        busy.value = false;
      }
    }

    Future<void> apply() async {
      final nameProblem = AppIdentityValidation.validateName(nameCtrl.text);
      if (nameProblem != null) {
        await _errorDialog(navigator, t.entry_invalid_name(nameProblem));
        return;
      }
      if (!hasImage) {
        await _errorDialog(navigator, t.entry_image_required);
        return;
      }
      busy.value = true;
      try {
        final previous = existing;
        final id = previous?.id ?? ShortcutChannelService.newEntryId();

        var imageRef = previous?.imageRef ?? '';
        var version = previous?.imageVersion ?? 1;
        var sourcePath = previous?.sourcePath ?? '';
        var cropLeft = previous?.cropLeft ?? 0.0;
        var cropTop = previous?.cropTop ?? 0.0;
        var cropRight = previous?.cropRight ?? 1.0;
        var cropBottom = previous?.cropBottom ?? 1.0;

        final result = editResult.value;
        if (result != null) {
          // Write the NEW files first; the superseded ones are removed only
          // after the entry is persisted. Deleting first would destroy the
          // existing icon if a write below fails.
          version += 1;
          imageRef = p.join('identity', 'entry_${id}_v$version.png');
          final target = File(AppIdentityPaths.filePath(imageRef));
          await target.parent.create(recursive: true);
          await target.writeAsBytes(result.png, flush: true);

          // Versioned so it never collides with the superseded source file
          // (which is deleted after the upsert along with the old icon).
          sourcePath = p.join(
              'identity',
              'source_${id}_v$version${result.sourceExtension.isEmpty ? '' : '.${result.sourceExtension}'}');
          final srcTarget = File(AppIdentityPaths.filePath(sourcePath));
          await srcTarget.parent.create(recursive: true);
          await srcTarget.writeAsBytes(result.sourceBytes, flush: true);

          cropLeft = result.cropRect.left;
          cropTop = result.cropRect.top;
          cropRight = result.cropRect.right;
          cropBottom = result.cropRect.bottom;
        }

        final now = DateTime.now();
        final isShared = shared.value;
        final entry = (previous ?? AppIdentityEntry(id: id, name: nameCtrl.text))
            .copyWith(
          name: nameCtrl.text,
          imageRef: imageRef,
          imageVersion: version,
          sourcePath: sourcePath,
          cropLeft: cropLeft,
          cropTop: cropTop,
          cropRight: cropRight,
          cropBottom: cropBottom,
          sharedWithDefault: isShared,
          // Seed is meaningless for a shared entry; drop it so toggling back
          // to independent starts clean.
          seedScenarioId: isShared ? null : seedScenarioId.value,
          seedTagId: isShared ? null : seedTagId.value,
          createdAt: previous?.createdAt ?? now,
          updatedAt: now,
        );
        await useAppIdentityStore().upsertEntry(entry);

        // Only now is the entry durable, so the superseded image/source files
        // can be removed without risking a dangling icon reference.
        if (previous != null && result != null) {
          await AppIdentityStore.deleteFilesFor(previous);
        }

        final failure = await applyEntryToPlatform(entry, result?.png, t);
        if (navigator.mounted) navigator.pop();
        if (failure != null) {
          await _errorDialog(navigator, failure);
        }
      } on ArgumentError catch (e) {
        await _errorDialog(navigator, t.entry_invalid_name('${e.message}'));
      } catch (e) {
        await _errorDialog(navigator, t.entry_apply_failed('$e'));
      } finally {
        busy.value = false;
      }
    }

    return KeyboardFormScaffold(
      fillViewport: fillViewport,
      title: Text(existing == null ? t.entry_new : t.entry_edit),
      // No close button on purpose: the form owns unsaved input, so only the
      // footer Cancel button may discard it (swipe/scrim dismissal is already
      // disabled by [showAdaptiveKeyboardForm]).
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Column(children: [
              if (editResult.value != null)
                _IconPreview(png: editResult.value!.png, size: 96)
              else if (existing?.imageRef.isNotEmpty ?? false)
                EntryAvatar(
                  imageRef: existing!.imageRef,
                  sourcePath: existing?.sourcePath ?? '',
                  size: 96,
                )
              else
                const SizedBox(
                  width: 96,
                  height: 96,
                  child: Icon(Icons.movie_filter_outlined, size: 48),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: busy.value ? null : pickAndCrop,
                icon: const Icon(Icons.image_outlined),
                label: Text(existing == null
                    ? t.entry_choose_image
                    : t.entry_change_image),
              ),
            ]),
          ),
          if (sourceMissing.value)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 16, color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      t.entry_image_missing,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('entryNameField'),
            controller: nameCtrl,
            focusNode: nameNode,
            maxLength: AppIdentityValidation.maxNameLength,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: t.entry_name_label,
              border: const OutlineInputBorder(),
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          _ModeSelector(
            shared: shared.value,
            onChanged: (v) => shared.value = v,
          ),
          if (!shared.value) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              key: const ValueKey('entrySeedScenario'),
              initialValue: scenarios.any((s) => s.id == seedScenarioId.value)
                  ? seedScenarioId.value
                  : null,
              decoration: InputDecoration(
                labelText: t.entry_seed_scenario,
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(t.entry_bind_none),
                ),
                ...scenarios.map(
                  (s) => DropdownMenuItem<String?>(
                    value: s.id,
                    child: Text(s.name),
                  ),
                ),
              ],
              onChanged: (v) => seedScenarioId.value = v,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              key: const ValueKey('entrySeedTag'),
              initialValue: tags.any((tag) => tag.id == seedTagId.value)
                  ? seedTagId.value
                  : null,
              decoration: InputDecoration(
                labelText: t.entry_seed_tag,
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem<int?>(
                  value: null,
                  child: Text(t.entry_bind_none),
                ),
                ...tags.map(
                  (tag) => DropdownMenuItem<int?>(
                    value: tag.id,
                    child: Text(tag.name),
                  ),
                ),
              ],
              onChanged: (v) => seedTagId.value = v,
            ),
            const SizedBox(height: 8),
            Text(
              t.entry_seed_note,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              t.entry_mode_shared_desc,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ],
      ),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Stays in the sticky footer (always visible) so the "image required"
          // reason is clear while the name field is focused.
          if (!hasImage)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                t.entry_image_required,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy.value
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: Text(t.cancel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                // Only the button rebuilds per keystroke (validity check), not
                // the whole form — keeps CJK input composition smooth.
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: nameCtrl,
                  builder: (context, value, _) {
                    final valid = AppIdentityValidation.validateName(
                            value.text) ==
                        null;
                    return FilledButton(
                      onPressed:
                          (valid && hasImage && !busy.value) ? apply : null,
                      child: Text(existing == null
                          ? t.entry_create_pin
                          : t.entry_save_update),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static bool _sourceMissing(AppIdentityEntry? e) {
    if (e == null || e.sourcePath.isEmpty) return false;
    final f = File(AppIdentityPaths.filePath(e.sourcePath));
    return !f.existsSync();
  }
}

/// Two-way state-mode choice: independent (default) vs share-default.
class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.shared, required this.onChanged});

  final bool shared;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    return Column(
      children: [
        RadioListTile<bool>(
          key: const ValueKey('entryModeIndependent'),
          value: false,
          groupValue: shared,
          contentPadding: EdgeInsets.zero,
          title: Text(t.entry_mode_independent),
          onChanged: (v) => onChanged(v ?? false),
        ),
        RadioListTile<bool>(
          key: const ValueKey('entryModeShared'),
          value: true,
          groupValue: shared,
          contentPadding: EdgeInsets.zero,
          title: Text(t.entry_mode_shared),
          onChanged: (v) => onChanged(v ?? false),
        ),
      ],
    );
  }
}

Future<Uint8List?> _readSourceBytes(String sourcePath) async {
  final f = File(AppIdentityPaths.filePath(sourcePath));
  if (!await f.exists()) return null;
  try {
    return await f.readAsBytes();
  } catch (_) {
    return null;
  }
}

class _IconPreview extends StatelessWidget {
  const _IconPreview({required this.png, required this.size});

  final Uint8List png;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.25),
      child: Image.memory(
        png,
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}

Future<void> _errorDialog(NavigatorState navigator, String message) {
  return showDialog<void>(
    context: navigator.context,
    builder: (ctx) => AlertDialog(
      title: Text(getLocalizations(ctx).entry_title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(getLocalizations(ctx).ok),
        ),
      ],
    ),
  );
}
