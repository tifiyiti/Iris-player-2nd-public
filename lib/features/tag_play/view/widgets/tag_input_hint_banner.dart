import 'package:flutter/material.dart';
import 'package:iris/utils/get_localizations.dart';

/// What the user chose when closing the command hint banner.
enum TagInputHintCloseChoice {
  /// Hide until the next app start only.
  session,

  /// Hide for good (writes `tagplay.inputHint`).
  permanent,
}

/// Closable example banner shown above the command bar.
///
/// Deliberately short-lived chrome: the sheet owns whether it is visible, so
/// this widget only renders content and reports the close tap.
class TagInputHintBanner extends StatelessWidget {
  const TagInputHintBanner({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      key: const ValueKey('tagInputHintBanner'),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      padding: const EdgeInsets.fromLTRB(10, 8, 2, 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.info_outline,
                size: 16, color: colorScheme.primary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t.tag_input_banner_title,
                  style: textTheme.labelLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  t.tag_input_banner_body,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('tagInputHintClose'),
            visualDensity: VisualDensity.compact,
            tooltip: t.tag_input_hint_close_title,
            icon: const Icon(Icons.close, size: 16),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

/// Asks whether the banner should stay hidden only for this session or
/// permanently. Returns null when the user backs out.
Future<TagInputHintCloseChoice?> showTagInputHintCloseDialog(
    BuildContext context) {
  return showDialog<TagInputHintCloseChoice>(
    context: context,
    builder: (dialogContext) {
      final t = getLocalizations(dialogContext);
      return AlertDialog(
        title: Text(t.tag_input_hint_close_title),
        content: Text(t.tag_input_hint_close_body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(t.tag_cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext)
                .pop(TagInputHintCloseChoice.session),
            child: Text(t.tag_input_hint_close_session),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext)
                .pop(TagInputHintCloseChoice.permanent),
            child: Text(t.tag_input_hint_close_permanent),
          ),
        ],
      );
    },
  );
}
