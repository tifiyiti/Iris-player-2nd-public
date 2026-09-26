import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iris/models/store/keyboard_form_geometry.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/platform.dart';
import 'package:iris/widgets/adaptive/keyboard_inset_padder.dart';
import 'package:iris/widgets/dialogs/draggable_dialog_shell.dart';

/// Width below which an input-bearing form opens as a bottom sheet instead of a
/// centered dialog. Mirrors the M3 medium window breakpoint (600).
const double kKeyboardFormBreakpoint = 600;

/// Maximum content width of the desktop dialog shell.
const double kKeyboardFormMaxWidth = 560;

/// Narrowest a draggable keyboard form may be squeezed to.
///
/// Matches the M3 dialog's own minimum, so the resize grip can never produce a
/// card narrower than a plain dialog would have been.
const double kKeyboardFormMinWidth = 280;

/// Horizontal breathing room between a draggable form and the screen edge.
const double kKeyboardFormDialogGutter = 16;

/// Share of the viewport HEIGHT a phone in landscape may spend on the form's
/// width.
///
/// The shell is picked by width, so a phone held sideways lands in the dialog
/// branch and gets a full-width, full-height card — a 560px slab wrapped around
/// one field, over half the screen. Deriving the width from the height instead
/// keeps it a panel. Portrait is untouched: there the form is a full-width
/// bottom sheet, and width is already correct.
const double kKeyboardFormLandscapeWidthFactor = 0.9;

/// True when [showAdaptiveKeyboardForm] would choose the bottom-sheet shell for
/// [context]. Callers build their form with `fillViewport: isKeyboardFormSheet`
/// so the scaffold's footer sticks to the sheet bottom.
bool isKeyboardFormSheet(BuildContext context) =>
    MediaQuery.sizeOf(context).width < kKeyboardFormBreakpoint;

/// Width a draggable keyboard form may never exceed on [viewport]: the M3 max
/// content width, itself bounded by the space actually on offer.
double keyboardFormWidthCeiling(Size viewport) => math.min(
      kKeyboardFormMaxWidth,
      math.max(
        kKeyboardFormMinWidth,
        viewport.width - kKeyboardFormDialogGutter * 2,
      ),
    );

/// Pixel width of a draggable keyboard form card.
///
/// [KeyboardFormGeometry.widthFraction] is the remembered preference; null (or a
/// non-finite value from a corrupt row) falls back to the auto width, which is
/// the ceiling everywhere except a phone held in landscape — there the default
/// is derived from the viewport HEIGHT instead, because the shell is picked by
/// width and a sideways phone would otherwise get a 560px slab around one field.
double resolveKeyboardFormWidth({
  required Size viewport,
  required bool mobile,
  double? widthFraction,
}) {
  final double ceiling = keyboardFormWidthCeiling(viewport);
  final bool landscapePhone = mobile && viewport.height < viewport.width;
  final double? fraction = widthFraction;
  if (fraction == null || !fraction.isFinite) {
    if (!landscapePhone) return ceiling;
    return math
        .min(ceiling, viewport.height * kKeyboardFormLandscapeWidthFactor)
        .clamp(kKeyboardFormMinWidth, ceiling)
        .toDouble();
  }
  // A remembered width is a share of the AVAILABLE width, then clamped: a form
  // widened on a desktop must still fit the phone it lands on.
  final double available = math.max(
    kKeyboardFormMinWidth,
    viewport.width - kKeyboardFormDialogGutter * 2,
  );
  return (available * fraction.clamp(0.0, 1.0))
      .clamp(kKeyboardFormMinWidth, ceiling)
      .toDouble();
}

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
///
/// [geometry] opts the dialog branch into the shared [DraggableDialogShell]: the
/// card becomes parkable by its header and resizable by a corner grip, and the
/// two gestures report through [onPositionChanged] / [onWidthChanged] — ONCE per
/// gesture, so a caller can persist without a write per frame. Leaving it null
/// keeps the plain centered dialog every other form already uses, and the
/// bottom-sheet branch ignores it (a full-width sheet has nowhere to park).
Future<T?> showAdaptiveKeyboardForm<T>({
  required BuildContext context,
  required Widget form,
  bool showDragHandle = true,
  bool enableDrag = true,
  bool isDismissible = true,
  KeyboardFormGeometry? geometry,
  ValueChanged<Offset>? onPositionChanged,
  ValueChanged<double?>? onWidthChanged,
}) {
  if (geometry != null && !isKeyboardFormSheet(context)) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: isDismissible,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black54,
      pageBuilder: (BuildContext _, __, ___) => DraggableDialogShell(
        initialFraction: geometry.offset,
        onCommit: (Offset fraction) => onPositionChanged?.call(fraction),
        dismissible: isDismissible,
        child: _DraggableFormCard(
          form: form,
          geometry: geometry,
          onWidthChanged: onWidthChanged,
        ),
      ),
    );
  }
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

/// The parkable, resizable card behind [DraggableDialogShell].
///
/// Built to SHRINK-WRAP the form: the shell measures its child to work out how
/// far the card can travel, and a child that filled the screen would leave it
/// no travel at all.
///
/// Performance: the card holds the caller's ONE cached form instance, passed
/// through untouched, so a resize frame relayouts the form without rebuilding
/// it — the invariant the bottom sheet and the dialog shell already keep.
class _DraggableFormCard extends StatefulWidget {
  const _DraggableFormCard({
    required this.form,
    required this.geometry,
    this.onWidthChanged,
  });

  final Widget form;
  final KeyboardFormGeometry geometry;
  final ValueChanged<double?>? onWidthChanged;

  @override
  State<_DraggableFormCard> createState() => _DraggableFormCardState();
}

class _DraggableFormCardState extends State<_DraggableFormCard> {
  /// Live width preference; null = auto. Only the resize gesture writes it, and
  /// only its end hands the value to the caller.
  double? _widthFraction;

  @override
  void initState() {
    super.initState();
    _widthFraction = widget.geometry.widthFraction;
  }

  /// Width available to the card on [viewport], i.e. what a stored fraction is a
  /// share of.
  double _available(Size viewport) => math.max(
        kKeyboardFormMinWidth,
        viewport.width - kKeyboardFormDialogGutter * 2,
      );

  void _resizeBy(double deltaPx, Size viewport) {
    final double ceiling = keyboardFormWidthCeiling(viewport);
    final double next =
        (_resolveWidth(viewport) + deltaPx).clamp(kKeyboardFormMinWidth, ceiling);
    setState(() => _widthFraction = (next / _available(viewport)).clamp(0.0, 1.0));
  }

  double _resolveWidth(Size viewport) => resolveKeyboardFormWidth(
        viewport: viewport,
        mobile: isMobilePlatform,
        widthFraction: _widthFraction,
      );

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Size viewport = MediaQuery.sizeOf(context);
    return RepaintBoundary(
      child: Material(
        elevation: 2,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        color: theme.colorScheme.surfaceContainerHigh,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: viewport.height * 0.92),
          child: SizedBox(
            // The resolved width is FORCED, not merely capped: a remembered
            // width the content could shrink-wrap away from would not be a
            // remembered width at all.
            width: _resolveWidth(viewport),
            child: Stack(
              children: <Widget>[
                // The SAME widget instance on every rebuild below, so a resize
                // frame never re-runs the form's build.
                widget.form,
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: _ResizeGrip(
                    onUpdate: (double delta) => _resizeBy(delta, viewport),
                    onEnd: () => widget.onWidthChanged?.call(_widthFraction),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom-right corner grip that widens the card horizontally.
///
/// A descendant of the form rather than the card itself: a pan over the whole
/// card would compete with the field's text selection and the footer buttons.
class _ResizeGrip extends StatelessWidget {
  const _ResizeGrip({required this.onUpdate, required this.onEnd});

  final ValueChanged<double> onUpdate;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final Color tint = Theme.of(context).colorScheme.onSurfaceVariant;
    return Semantics(
      label: getLocalizations(context).keyboard_form_resize,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: GestureDetector(
          key: const ValueKey('keyboard_form_resize_grip'),
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (DragUpdateDetails details) => onUpdate(details.delta.dx),
          onPanEnd: (_) => onEnd(),
          onPanCancel: onEnd,
          child: Padding(
            // The padding IS the touch target; the glyph alone is 16px.
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 4),
            child: Icon(Icons.drag_handle, size: 16, color: tint),
          ),
        ),
      ),
    );
  }
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
    // Presence of the scope IS the flag: a form rendered inside the draggable
    // shell grows a grip, and every other form's header stays as it was.
    final DraggableDialogScope? drag = DraggableDialogScope.maybeOf(context);
    return Column(
      mainAxisSize: fillViewport ? MainAxisSize.max : MainAxisSize.min,
      children: [
        header ??
            _Header(
              title: title!,
              onClose: onClose,
              closeTooltip: closeTooltip,
              drag: drag,
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

/// Sticky header: an optional drag grip, the title, and the close button.
///
/// The grip is a DESCENDANT of the shell and the padded row is the touch
/// target, so a pan here can never steal a drag from the controls below — the
/// same rule the speed picker card follows.
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.onClose,
    required this.closeTooltip,
    required this.drag,
  });

  final Widget title;
  final VoidCallback? onClose;
  final String? closeTooltip;
  final DraggableDialogScope? drag;

  static const EdgeInsets _pad = EdgeInsets.fromLTRB(20, 12, 4, 4);

  @override
  Widget build(BuildContext context) {
    final Widget row = Row(
      children: <Widget>[
        if (drag != null) ...<Widget>[
          Icon(
            Icons.drag_indicator_rounded,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: DefaultTextStyle.merge(
            style: Theme.of(context).textTheme.titleMedium,
            child: title,
          ),
        ),
        if (onClose != null)
          IconButton(
            tooltip: closeTooltip,
            icon: const Icon(Icons.close),
            onPressed: onClose,
          ),
      ],
    );
    if (drag == null) return Padding(padding: _pad, child: row);
    return Semantics(
      label: getLocalizations(context).keyboard_form_drag,
      child: MouseRegion(
        cursor: SystemMouseCursors.move,
        child: GestureDetector(
          key: const ValueKey('keyboard_form_drag_handle'),
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (DragUpdateDetails details) =>
              drag!.onDragUpdate(details.delta),
          onPanEnd: (_) => drag!.onDragEnd(),
          onPanCancel: drag!.onDragEnd,
          child: Padding(padding: _pad, child: row),
        ),
      ),
    );
  }
}

/// A zero-input action rendered in its own row under the field of
/// [showKeyboardTextPrompt] — for prompts where typing is optional, e.g. the
/// browser jump's "first page" / "last page" shortcuts.
///
/// Selecting one closes the prompt and only THEN runs [onSelected], so the
/// callback may start a fetch or navigation without racing the exit transition.
/// The prompt therefore resolves with `null`, exactly like Cancel: a caller that
/// also accepts typed input never has to decode a sentinel value.
@immutable
class KeyboardTextPromptAction {
  const KeyboardTextPromptAction({
    required this.label,
    required this.onSelected,
    this.icon,
    this.enabled = true,
  });

  final String label;

  /// Optional leading glyph; the action reads better with one (e.g.
  /// [Icons.first_page]).
  final IconData? icon;

  /// Runs after the route has been popped.
  final VoidCallback onSelected;

  /// False renders the action greyed out and swallows taps.
  final bool enabled;
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
  List<KeyboardTextPromptAction>? bodyActions,
  KeyboardFormGeometry? geometry,
  ValueChanged<Offset>? onPositionChanged,
  ValueChanged<double?>? onWidthChanged,
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
      bodyActions: bodyActions,
      validate: validate,
    ),
    geometry: geometry,
    onPositionChanged: onPositionChanged,
    onWidthChanged: onWidthChanged,
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
    this.bodyActions,
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
  final List<KeyboardTextPromptAction>? bodyActions;
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

  /// Pop first, act second: the action may start a fetch or a navigation, and
  /// running it while the exit transition still owns the route invites
  /// "setState during pop"-style errors.
  void _runAction(KeyboardTextPromptAction action) {
    Navigator.of(context).pop();
    action.onSelected();
  }

  Widget _buildActionButton(KeyboardTextPromptAction action) {
    // `null` onPressed is what renders the action greyed out and inert.
    final onPressed = action.enabled ? () => _runAction(action) : null;
    final icon = action.icon;
    if (icon == null) {
      return TextButton(onPressed: onPressed, child: _labelOf(action));
    }
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: _labelOf(action),
    );
  }

  /// Long translations must ellipsize rather than overflow: the actions share
  /// one row, so each gets a fixed slice of the form's width.
  Widget _labelOf(KeyboardTextPromptAction action) => Text(
        action.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );

  Widget _buildBody() {
    final field = TextField(
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
    );
    final actions = widget.bodyActions;
    if (actions == null || actions.isEmpty) return field;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        field,
        const SizedBox(height: 8),
        Row(
          children: [
            for (final action in actions)
              Expanded(child: _buildActionButton(action)),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    return KeyboardFormScaffold(
      // Built once by [showAdaptiveKeyboardForm]; a single field shrinks to
      // content in both shells (no MediaQuery read).
      title: Text(widget.title),
      onClose: () => Navigator.of(context).pop(),
      body: _buildBody(),
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
