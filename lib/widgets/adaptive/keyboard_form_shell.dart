import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/platform.dart';
import 'package:iris/widgets/adaptive/keyboard_inset_padder.dart';

/// Width below which an input-bearing form opens as a bottom sheet instead of a
/// centered dialog. Mirrors the M3 medium window breakpoint (600).
const double kKeyboardFormBreakpoint = 600;

/// Maximum content width of the desktop dialog shell.
const double kKeyboardFormMaxWidth = 560;

/// True when [showAdaptiveKeyboardForm] would choose the bottom-sheet shell for
/// [context]. Callers build their form with `fillViewport: isKeyboardFormSheet`
/// so the scaffold's footer sticks to the sheet bottom.
bool isKeyboardFormSheet(BuildContext context) =>
    MediaQuery.sizeOf(context).width < kKeyboardFormBreakpoint;

/// Adaptive shell for input-bearing popups (the "keyboard form" pattern).
///
/// Phones (< [kKeyboardFormBreakpoint]) get a scroll-controlled bottom sheet;
/// wider layouts get a centered dialog. Both shells hold ONE cached [form]
/// instance, so keyboard/inset frames only repad — they never rebuild a field.
///
/// The [form] must be built ONCE at the call site and must NOT read
/// `MediaQuery` (width branching via `LayoutBuilder`, theme via `Theme`); see
/// `KeyboardFormScaffold`. Returns the route's pop result, like `showDialog`.
///
/// [enableDrag] / [isDismissible] let a form that holds unsaved input opt out
/// of gesture dismissal (swipe-down and scrim-tap) so only an explicit button
/// can cancel it; both default to the platform-standard behaviour.
Future<T?> showAdaptiveKeyboardForm<T>({
  required BuildContext context,
  required Widget form,
  bool showDragHandle = true,
  bool enableDrag = true,
  bool isDismissible = true,
}) {
  if (isKeyboardFormSheet(context)) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: enableDrag,
      isDismissible: isDismissible,
      showDragHandle: showDragHandle,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _KeyboardFormSheet(form: form),
    );
  }
  return showDialog<T>(
    context: context,
    barrierDismissible: isDismissible,
    builder: (_) => _KeyboardFormDialog(form: form),
  );
}

/// Centered-dialog shell for wide screens. The cached form is passed through
/// [KeyboardInsetPadder]; inside a `Dialog` that padder is inert (the `Dialog`
/// removes view insets from its child and pads itself), which is intentional.
class _KeyboardFormDialog extends StatefulWidget {
  const _KeyboardFormDialog({required this.form});

  final Widget form;

  @override
  State<_KeyboardFormDialog> createState() => _KeyboardFormDialogState();
}

class _KeyboardFormDialogState extends State<_KeyboardFormDialog> {
  // Built EXACTLY ONCE: keyboard frames below never rebuild the form.
  late final Widget _form = widget.form;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final narrow = size.width < kKeyboardFormBreakpoint;
    return Dialog(
      insetPadding: narrow
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 12)
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: kKeyboardFormMaxWidth,
          maxHeight: size.height * 0.92,
        ),
        child: KeyboardInsetPadder(child: _form),
      ),
    );
  }
}

/// Bottom-sheet shell for phones: keyboard avoidance is the single
/// [KeyboardInsetPadder] — no `DraggableScrollableSheet` (it re-resolves its
/// extent and rebuilds content on every keyboard frame).
class _KeyboardFormSheet extends StatefulWidget {
  const _KeyboardFormSheet({required this.form});

  final Widget form;

  @override
  State<_KeyboardFormSheet> createState() => _KeyboardFormSheetState();
}

class _KeyboardFormSheetState extends State<_KeyboardFormSheet> {
  late final Widget _form = widget.form;

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

/// Shared chrome for a keyboard form: a sticky header (title, plus a close
/// button when [onClose] is supplied), a scrollable body, and a sticky footer.
/// Reads NO `MediaQuery`, so it is safe inside a cached form.
class KeyboardFormScaffold extends StatelessWidget {
  const KeyboardFormScaffold({
    super.key,
    required this.body,
    required this.footer,
    this.title,
    this.header,
    this.onClose,
    this.closeTooltip,
    this.fillViewport = false,
  }) : assert(title != null || header != null,
            'Provide either a title or a custom header');

  /// Sticky header title (wrapped in `titleMedium` unless it carries its own
  /// style). Ignored when [header] is supplied.
  final Widget? title;

  /// Fully custom sticky header. Takes precedence over [title].
  final Widget? header;

  /// Scrollable middle. The scaffold supplies the `SingleChildScrollView`.
  final Widget body;

  /// Sticky footer (e.g. the action buttons row).
  final Widget footer;

  /// Close button callback; hidden when null.
  final VoidCallback? onClose;

  final String? closeTooltip;

  /// True inside the bottom-sheet shell (fill the sheet); false inside the
  /// dialog shell (shrink to content).
  final bool fillViewport;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: fillViewport ? MainAxisSize.max : MainAxisSize.min,
      children: [
        header ??
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 4, 4),
              child: Row(
                children: [
                  Expanded(
                    child: DefaultTextStyle.merge(
                      style: Theme.of(context).textTheme.titleMedium,
                      child: title!,
                    ),
                  ),
                  if (onClose != null)
                    IconButton(
                      tooltip: closeTooltip,
                      icon: const Icon(Icons.close),
                      onPressed: onClose,
                    ),
                ],
              ),
            ),
        const Divider(height: 1),
        Flexible(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: body,
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: footer,
        ),
      ],
    );
  }
}

/// A one-field text prompt built on the canonical keyboard shell.
///
/// Use for simple "rename / enter a value" popups INSTEAD of `AlertDialog`:
/// the dialog reintroduces `IntrinsicWidth` re-measurement and inset-driven
/// descendant rebuilds. Returns the trimmed text, or null when cancelled.
Future<String?> showKeyboardTextPrompt({
  required BuildContext context,
  required String title,
  String initialValue = '',
  String? label,
  String? hint,
  String? helper,
  String? confirmLabel,
  String? cancelLabel,
  TextInputType? keyboardType,
  List<TextInputFormatter>? inputFormatters,
  int? maxLength,
  String? Function(String value)? validate,
}) {
  return showAdaptiveKeyboardForm<String>(
    context: context,
    form: _KeyboardTextPromptForm(
      title: title,
      initialValue: initialValue,
      label: label,
      hint: hint,
      helper: helper,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLength: maxLength,
      validate: validate,
    ),
  );
}

class _KeyboardTextPromptForm extends StatefulWidget {
  const _KeyboardTextPromptForm({
    required this.title,
    this.initialValue = '',
    this.label,
    this.hint,
    this.helper,
    this.confirmLabel,
    this.cancelLabel,
    this.keyboardType,
    this.inputFormatters,
    this.maxLength,
    this.validate,
  });

  final String title;
  final String initialValue;
  final String? label;
  final String? hint;
  final String? helper;
  final String? confirmLabel;
  final String? cancelLabel;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final String? Function(String value)? validate;

  @override
  State<_KeyboardTextPromptForm> createState() =>
      _KeyboardTextPromptFormState();
}

class _KeyboardTextPromptFormState extends State<_KeyboardTextPromptForm> {
  // Owned by the State (not the helper): the shell keeps the widget alive
  // through the route's exit transition, so disposing in `whenComplete` would
  // free the controller while it is still in the tree.
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    final error = widget.validate?.call(value);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    return KeyboardFormScaffold(
      // Built once by [showAdaptiveKeyboardForm]; a single field shrinks to
      // content in both shells (no MediaQuery read).
      title: Text(widget.title),
      onClose: () => Navigator.of(context).pop(),
      body: TextField(
        controller: _controller,
        autofocus: !isMobilePlatform,
        keyboardType: widget.keyboardType,
        inputFormatters: widget.inputFormatters,
        maxLength: widget.maxLength,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: widget.label,
          hintText: widget.hint,
          helperText: widget.helper,
          errorText: _error,
        ),
      ),
      footer: Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 4,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(widget.cancelLabel ?? t.cancel),
          ),
          FilledButton(
            onPressed: _submit,
            child: Text(widget.confirmLabel ?? t.save),
          ),
        ],
      ),
    );
  }
}
