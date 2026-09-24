import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/meta_settings/view/setting_texts.dart';
import 'package:iris/features/playback_tools/services/screenshot_paths.dart';
import 'package:iris/features/playback_tools/services/screenshot_service.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/platform.dart' show isAndroid;
import 'package:iris/widgets/adaptive/keyboard_inset_padder.dart';
import 'package:logging/logging.dart';
import 'package:saf_util/saf_util.dart';

final Logger _log = Logger('playback_tools.screenshot_dir_dialog');

/// Screenshot save-directory editor (per-platform custom dir).
///
/// Keyboard structure mirrors `vm_mark_color_dialog.dart`: the heavy form is
/// built EXACTLY ONCE and cached in shell state, while keyboard height is
/// consumed by ONE AnimatedPadding in the shell — keyboard frames move
/// pixels without rebuilding a single field. When the path input holds
/// focus, the header folds away to free vertical space on 360px phones.
/// Phones get a bottom sheet, desktops a centered dialog — same form.
Future<void> showScreenshotSavePathDialog(BuildContext context,
    {required bool isMobile}) async {
  final w = MediaQuery.sizeOf(context).width;
  if (w < 600) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ScreenshotDirSheet(isMobile: isMobile),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (_) => _ScreenshotDirDialog(isMobile: isMobile),
  );
}

/// Centered-dialog shell for wide screens (desktop / tablet landscape).
class _ScreenshotDirDialog extends StatefulWidget {
  const _ScreenshotDirDialog({required this.isMobile});

  final bool isMobile;

  @override
  State<_ScreenshotDirDialog> createState() => _ScreenshotDirDialogState();
}

class _ScreenshotDirDialogState extends State<_ScreenshotDirDialog> {
  late final Widget _form = ScreenshotDirForm(isMobile: widget.isMobile);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: size.height * 0.92,
        ),
        child: KeyboardInsetPadder(child: _form),
      ),
    );
  }
}

/// Bottom-sheet shell for phones: keyboard avoidance is the single
/// [KeyboardInsetPadder] — no DraggableScrollableSheet (it
/// re-resolves extent + rebuilds content on every keyboard frame).
class _ScreenshotDirSheet extends StatefulWidget {
  const _ScreenshotDirSheet({required this.isMobile});

  final bool isMobile;

  @override
  State<_ScreenshotDirSheet> createState() => _ScreenshotDirSheetState();
}

class _ScreenshotDirSheetState extends State<_ScreenshotDirSheet> {
  late final Widget _form =
      ScreenshotDirForm(isMobile: widget.isMobile, fillViewport: true);

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return KeyboardInsetPadder(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: height * 0.92),
        child: _form,
      ),
    );
  }
}

/// Picks a directory through the platform picker: Android SAF tree
/// (persistable permission so the grant survives restarts), desktops the
/// native folder dialog. Null on cancel or failure (logged, never thrown).
Future<String?> pickScreenshotDirectory() async {
  try {
    if (isAndroid) {
      // Write permission is required: the picker otherwise grants read-only,
      // so a chosen dir could never receive a screenshot.
      final dir = await SafUtil().pickDirectory(
          writePermission: true, persistablePermission: true);
      return dir?.uri;
    }
    return await FilePicker.platform.getDirectoryPath();
  } catch (e) {
    _log.warning('screenshot dir pick failed: $e');
    return null;
  }
}

/// Platform pick + SAF resolution for the pick button; extracted so the test
/// seam ([ScreenshotDirForm.debugPickResolved]) can replace the pair without
/// duplicating either implementation. Null on cancel/failure.
Future<ResolvedPick?> _pickAndResolve() async {
  final raw = await pickScreenshotDirectory();
  if (raw == null) return null;
  return resolvePickedScreenshotDir(raw);
}

/// Shared editor form (sticky header / scrollable fields / sticky footer).
/// Built once per shell — reads NO MediaQuery: width branching via
/// LayoutBuilder, theme via Theme (stable across keyboard frames).
class ScreenshotDirForm extends HookWidget {
  const ScreenshotDirForm(
      {super.key, required this.isMobile, this.fillViewport = false});

  final bool isMobile;

  /// True inside the bottom-sheet shell (fill the sheet); false inside the
  /// dialog shell (shrink to content).
  final bool fillViewport;

  /// Test seam: counts form rebuilds to prove keyboard frames don't re-run
  /// the form. Null in prod.
  static void Function()? debugOnFormBuild;

  /// Test seam: overrides the platform picker + SAF resolution for the pick
  /// button. Null in prod (the real picker + [resolvePickedScreenshotDir] run).
  static Future<ResolvedPick?> Function()? debugPickResolved;

  @override
  Widget build(BuildContext context) {
    debugOnFormBuild?.call();
    final t = getLocalizations(context);
    final stored = useAppStore().select(
        context,
        (s) =>
            isMobile ? s.screenshotMobileDir : s.screenshotDesktopDir);
    final hideChrome = useState(false);
    final pathNode = useFocusNode();
    final pathCtrl = useTextEditingController();
    useEffect(() {
      if (!pathNode.hasFocus && pathCtrl.text != stored) {
        pathCtrl.text = stored;
      }
      return null;
    }, [stored]);
    useEffect(() {
      void onFocus() {
        if (hideChrome.value != pathNode.hasFocus) {
          hideChrome.value = pathNode.hasFocus;
        }
        if (pathNode.hasFocus) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (pathNode.context != null) {
              Scrollable.ensureVisible(pathNode.context!,
                  duration: const Duration(milliseconds: 200));
            }
          });
        }
      }

      pathNode.addListener(onFocus);
      return () => pathNode.removeListener(onFocus);
    }, [pathNode]);

    Future<void> error(String msg) async {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogCtx) {
          final t = getLocalizations(dialogCtx);
          return AlertDialog(
            title: Text(t.shot_invalid_dir_title),
            content: Text(msg),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(t.dlg_storage_info_got_it)),
            ],
          );
        },
      );
    }

    void applyStore(String v) {
      final store = useAppStore();
      if (isMobile) {
        store.updateScreenshotMobileDir(v);
      } else {
        store.updateScreenshotDesktopDir(v);
      }
    }

    Future<void> pickUp() async {
      final resolved =
          await (ScreenshotDirForm.debugPickResolved ?? _pickAndResolve)();
      if (resolved == null) return;
      // A pick that resolved to an unwritable directory is REJECTED outright:
      // nothing is stored, the previously effective save folder stays in force,
      // and the user is told why (never a silent revert). The write chain would
      // otherwise burn a doomed attempt at capture time.
      if (resolved.skipped) {
        if (!context.mounted) return;
        await error(getLocalizations(context).shot_pick_unwritable);
        return;
      }
      final normalized =
          normalizeScreenshotInput(resolved.path, isAndroid: isAndroid);
      if (normalized == null) {
        if (!context.mounted) return;
        final t = getLocalizations(context);
        await error(isAndroid
            ? t.shot_pick_error_android
            : t.shot_pick_error_desktop);
        return;
      }
      applyStore(normalized);
    }

    void applyInput() {
      final t = getLocalizations(context);
      final normalized = normalizeScreenshotInput(pathCtrl.text,
          isAndroid: isAndroid);
      if (normalized == null) {
        error(t.shot_path_error(
            isAndroid ? '' : t.shot_path_error_desktop_note));
        return;
      }
      applyStore(normalized);
      pathNode.unfocus();
    }

    void restoreDefault() => applyStore('');

    return Column(
      mainAxisSize: fillViewport ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (!hideChrome.value) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
            child: Row(
              children: [
                Expanded(
                    child: Text(
                        SettingTexts.title('screenshot_save_path', t))),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
        ],
        Flexible(
          child: SingleChildScrollView(
            keyboardDismissBehavior:
                ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: LayoutBuilder(builder: (context, constraints) {
              final narrow = constraints.maxWidth < 420;
              Widget currentDirRow() {
                final label = displayScreenshotDir(
                  stored,
                  defaultLabel: isMobile
                      ? t.ed_shot_default_mobile
                      : t.ed_shot_default_desktop,
                  safFallbackLabel: t.shot_saf_dir_fallback,
                );
                return Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        label,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: t.shot_copy_tip,
                      icon: const Icon(Icons.copy_rounded, size: 20),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: stored));
                      },
                    ),
                  ],
                );
              }

              Widget pickButton() {
                return ElevatedButton.icon(
                  key: const ValueKey('screenshotDirPickUp'),
                  onPressed: pickUp,
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: Text(t.shot_pick_label),
                );
              }

              Widget inputRow() {
                return Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('screenshotDirInput'),
                        controller: pathCtrl,
                        focusNode: pathNode,
                        // Shell-driven, not platform-driven: the phone
                        // sheet never auto-pops the keyboard (it would
                        // shove the form up before first paint); the
                        // desktop dialog focuses immediately.
                        autofocus: !isMobile,
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: t.shot_paste_label,
                          hintText: t.shot_paste_hint,
                        ),
                        onSubmitted: (_) => applyInput(),
                      ),
                    ),
                    TextButton(
                      onPressed: applyInput,
                      child: Text(t.shot_apply),
                    ),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t.shot_current_dir,
                      style: Theme.of(context).textTheme.titleSmall),
                  currentDirRow(),
                  Text(
                    SettingTexts.subtitle(
                        'screenshot_save_path_desc', t),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  if (narrow)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        pickButton(),
                        const SizedBox(height: 8),
                        inputRow(),
                      ],
                    )
                  else
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        pickButton(),
                        SizedBox(width: 320, child: inputRow()),
                      ],
                    ),
                ],
              );
            }),
          ),
        ),
        const Divider(height: 1),
        // Fixed footer padding: keyboard avoidance lives in the shell's
        // [KeyboardInsetPadder]. Reading viewInsets here would
        // rebuild the whole form on every keyboard frame.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('screenshotDirReset'),
                  onPressed: restoreDefault,
                  child: Text(t.shot_reset),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(t.close),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
