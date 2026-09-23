import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iris/features/tag_play/model/domain/tag_command.dart';
import 'package:iris/utils/get_localizations.dart';

/// Turns a mid-line operator keystroke into a fresh command: `+1.2` then `*`
/// becomes `*`. The numpad entry keys are intercepted as key events (they must
/// restart the line even when the field has no focus); this formatter is the
/// deterministic backstop for the same intent typed on the main keyboard.
class _TagOperatorResetFormatter extends TextInputFormatter {
  const _TagOperatorResetFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final operator = tagOperatorResetOnEdit(oldValue.text, newValue.text);
    if (operator == null) return newValue;
    return TextEditingValue(
      text: operator,
      selection: const TextSelection.collapsed(offset: 1),
    );
  }
}

/// Command line of the tag-play sheet: one dense field that accepts the
/// grammar of `parseTagCommand` (`*3`, `+1.2.5`, `-2.4`).
///
/// Keyboard handling lives here on purpose:
///  - Enter submits through [TextField.onSubmitted] (the engine's `done`
///    action — numpad Enter included);
///  - Escape CLEARS the field while it holds text, and is swallowed so the
///    enclosing Popup route does not close the sheet on the first press.
///
/// The sheet-level key scope owns `/` (close) and the numpad operator keys
/// (they must restart the line even when this field has lost focus), plus the
/// post-submit refocus; this field contributes the operator-collapse formatter.
class TagInputBar extends StatelessWidget {
  const TagInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.errorText,
    required this.onSubmit,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String? errorText;
  final ValueChanged<String> onSubmit;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          if (event.logicalKey != LogicalKeyboardKey.escape) {
            return KeyEventResult.ignored;
          }
          if (controller.text.isEmpty) {
            // Empty field: let Esc fall through to the Popup's close handler.
            return KeyEventResult.ignored;
          }
          controller.clear();
          onChanged('');
          return KeyEventResult.handled;
        },
        child: TextField(
          key: const ValueKey('tagInputField'),
          controller: controller,
          focusNode: focusNode,
          // EditableText defaults this to TRUE on desktop/web, which would
          // select the prefilled operator on focus so the first keystroke
          // overwrites it ('+' → '1'). The operator IS the pre-selected mode,
          // so it must survive: keep the caret at the end and let digits
          // append ('+' → '+1').
          selectAllOnFocus: false,
          maxLines: 1,
          textInputAction: TextInputAction.done,
          onSubmitted: onSubmit,
          onChanged: onChanged,
          inputFormatters: [
            const _TagOperatorResetFormatter(),
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.*+\-]')),
          ],
          style: Theme.of(context).textTheme.bodyMedium,
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            prefixIcon: Icon(Icons.tag_rounded,
                size: 18, color: colorScheme.onSurfaceVariant),
            hintText: t.tag_input_placeholder,
            hintStyle: TextStyle(color: Theme.of(context).disabledColor),
            errorText: errorText,
            errorMaxLines: 2,
            suffixIcon: IconButton(
              tooltip: t.tag_input_send,
              icon: const Icon(Icons.keyboard_return_rounded, size: 18),
              onPressed: () => onSubmit(controller.text),
            ),
          ),
        ),
      ),
    );
  }
}
