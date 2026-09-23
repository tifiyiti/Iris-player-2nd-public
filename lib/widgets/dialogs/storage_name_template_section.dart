import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/storages/storage_name_prefs.dart';
import 'package:iris/utils/get_localizations.dart';

/// Embedded "name template" editor for the WebDAV / FTP storage dialogs.
///
/// Purely presentational: the parent owns the session draft and decides when to
/// persist. The chips are wrapped in a non-focusable [Focus] so tapping one
/// never blurs the active text field (which would collapse / re-pop the IME).
class StorageNameTemplateSection extends HookWidget {
  const StorageNameTemplateSection({
    super.key,
    required this.tags,
    required this.separatorController,
    required this.global,
    required this.previewName,
    required this.onToggleTag,
    required this.onSeparatorChanged,
    required this.onGlobalChanged,
    required this.onReset,
    this.onSeparatorCommitted,
  });

  /// Currently selected tags, in composition (lit) order.
  final List<StorageNameTag> tags;
  final TextEditingController separatorController;
  final bool global;
  final String previewName;
  final ValueChanged<StorageNameTag> onToggleTag;

  /// Called on every keystroke: must only update in-session state (no I/O).
  final ValueChanged<String> onSeparatorChanged;

  /// Called on blur/submit: flushes the separator to storage.
  final VoidCallback? onSeparatorCommitted;
  final ValueChanged<bool> onGlobalChanged;
  final VoidCallback onReset;

  String _tagLabel(AppLocalizations t, StorageNameTag tag) => switch (tag) {
        StorageNameTag.type => t.storage_name_tag_type,
        StorageNameTag.account => t.storage_name_tag_account,
        StorageNameTag.host => t.storage_name_tag_host,
        StorageNameTag.port => t.storage_name_tag_port,
        StorageNameTag.path => t.storage_name_tag_path,
      };

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final theme = Theme.of(context);
    final separatorFocus = useFocusNode();
    // Commit once on blur — the separator holds a controller, so storage sees a
    // single write when the user leaves the field, never one per keystroke.
    useEffect(() {
      void onFocus() {
        if (!separatorFocus.hasFocus) onSeparatorCommitted?.call();
      }

      separatorFocus.addListener(onFocus);
      return () => separatorFocus.removeListener(onFocus);
    }, const []);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                t.storage_name_template_title,
                style: theme.textTheme.titleSmall,
              ),
            ),
            TextButton(
              onPressed: onReset,
              child: Text(t.storage_name_reset),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Focus(
          canRequestFocus: false,
          descendantsAreFocusable: false,
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final tag in StorageNameTag.values)
                _chip(t, theme, tag, tags.indexOf(tag)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final separator = TextField(
              controller: separatorController,
              focusNode: separatorFocus,
              maxLength: StorageNamePrefs.maxSeparatorLength,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: t.storage_name_separator_label,
                // Hide the "n/9" counter to keep the 360px layout compact.
                counterText: '',
              ),
              onChanged: onSeparatorChanged,
              onSubmitted: (_) => onSeparatorCommitted?.call(),
            );
            final globalToggle = _globalToggle(t);
            if (constraints.maxWidth < 420) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  separator,
                  const SizedBox(height: 4),
                  globalToggle,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: separator),
                const SizedBox(width: 8),
                Flexible(child: globalToggle),
              ],
            );
          },
        ),
        const SizedBox(height: 4),
        Text(
          '${t.storage_name_preview_label}: $previewName',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _globalToggle(AppLocalizations t) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Focus(
          canRequestFocus: false,
          descendantsAreFocusable: false,
          child: Checkbox(
            value: global,
            onChanged: (value) => onGlobalChanged(value ?? false),
          ),
        ),
        Flexible(
          child: Text(
            t.storage_name_template_global,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _chip(
    AppLocalizations t,
    ThemeData theme,
    StorageNameTag tag,
    int order,
  ) {
    final selected = order >= 0;
    return FilterChip(
      label: Text(_tagLabel(t, tag)),
      selected: selected,
      showCheckmark: false,
      avatar: selected
          ? CircleAvatar(
              radius: 9,
              backgroundColor: theme.colorScheme.primary,
              child: Text(
                '${order + 1}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimary,
                ),
              ),
            )
          : null,
      onSelected: (_) => onToggleTag(tag),
    );
  }
}
