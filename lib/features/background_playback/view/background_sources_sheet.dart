import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/features/background_playback/actions/background_playback_actions.dart';
import 'package:iris/features/background_playback/model/source/bg_source_rule.dart';
import 'package:iris/features/background_playback/store/bg_source_prefs.dart';
import 'package:iris/features/background_playback/view/bg_source_labels.dart';
import 'package:iris/features/background_playback/view/bg_source_rule_editor.dart';
import 'package:iris/features/background_playback/view/widgets/bg_source_banner.dart';
import 'package:iris/features/tag_play/model/domain/tag_play_tag.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/utils/get_localizations.dart';

/// 副音 candidate-source manager: an ordered, pinnable, toggleable rule list
/// with a global auto-dedupe switch, a manual refresh, and the zero-active
/// fallback banner.
///
/// Rules are read from the `bg_source_rules` Drift table via a live stream, so
/// edits show immediately here; the actual candidate list refreshes only on
/// "Update now" or the next 副音 start.
Future<void> showBackgroundSourcesSheet(BuildContext context) async {
  final width = MediaQuery.sizeOf(context).width;
  if (width < kBgEditorSheetBreakpoint) {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _SourcesBody(),
    );
  } else {
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
          child: const _SourcesBody(),
        ),
      ),
    );
  }
}

class _SourcesBody extends HookWidget {
  const _SourcesBody();

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final rulesAsync = useStream(useMemoized(
      () => DbModule.bgSourceRuleRepo.watchRules(),
      const [],
    ));
    final tagsFuture = useFuture(
      useMemoized(() => DbModule.tagPlayRepo.tags(), const []),
    );
    final autoDedupe = useState(false);
    useEffect(() {
      var cancelled = false;
      BgSourcePrefs.autoDedupe().then((v) {
        if (!cancelled) autoDedupe.value = v;
      });
      return () => cancelled = true;
    }, const []);

    final rules = rulesAsync.data ?? const <BgSourceRule>[];
    final tags = tagsFuture.data ?? const <TagPlayTag>[];
    final tagName = {for (final g in tags) g.id: g.name};
    final enabledCount = rules.where((r) => r.enabled).length;

    Future<void> openEditor(BgSourceRule? initial) async {
      final order = initial?.sortOrder ??
          await DbModule.bgSourceRuleRepo.nextSortOrder();
      if (!context.mounted) return;
      await openBgSourceRuleEditor(context, initial: initial, sortOrder: order);
    }

    Future<void> duplicate(BgSourceRule rule) async {
      final order = await DbModule.bgSourceRuleRepo.nextSortOrder();
      final base = bgSourceRuleLabel(rule, t);
      await DbModule.bgSourceRuleRepo.saveRule(rule.copyWith(
        id: 'bgsrc_${DateTime.now().microsecondsSinceEpoch}',
        name: t.bg_src_copy_name(base),
        builtin: false,
        enabled: false,
        sortOrder: order,
        createdAt: DateTime.now(),
      ));
    }

    Future<void> remove(BgSourceRule rule) async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(t.bg_src_delete_title),
          content: Text(t.bg_src_delete_body(bgSourceRuleLabel(rule, t))),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(t.vm_editor_cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(t.bg_src_delete),
            ),
          ],
        ),
      );
      if (ok == true) await DbModule.bgSourceRuleRepo.deleteRule(rule.id);
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t.set_bg_sources,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              t.set_bg_sources_desc,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.bg_src_auto_dedupe,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      Text(
                        t.bg_src_auto_dedupe_desc,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: autoDedupe.value,
                  onChanged: (v) {
                    autoDedupe.value = v;
                    BgSourcePrefs.setAutoDedupe(v);
                  },
                ),
              ],
            ),
            if (enabledCount == 0) const BgSourceFallbackBanner(),
            const Divider(height: 1),
            Flexible(
              child: rules.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          t.bg_sources_empty_hint,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: rules.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) => _RuleRow(
                        rule: rules[i],
                        label: bgSourceRuleLabel(rules[i], t),
                        summary: bgSourceRuleSummary(rules[i], t, tagName),
                        onEdit: () => openEditor(rules[i]),
                        onDuplicate: () => duplicate(rules[i]),
                        onDelete: () => remove(rules[i]),
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () =>
                        BackgroundPlaybackActions.refresh(context),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(t.bg_src_refresh_now),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => openEditor(null),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(t.bg_sources_add),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({
    required this.rule,
    required this.label,
    required this.summary,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
  });

  final BgSourceRule rule;
  final String label;
  final String summary;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(bgSourceKindIcon(rule.kind), size: 20),
      title: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: rule.enabled
            ? null
            : TextStyle(color: Theme.of(context).disabledColor),
      ),
      subtitle: Text(
        summary,
        style: Theme.of(context).textTheme.labelSmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: rule.pinned ? t.bg_src_unpin : t.bg_src_pin,
            icon: Icon(
              rule.pinned ? Icons.push_pin : Icons.push_pin_outlined,
              size: 18,
            ),
            onPressed: () => DbModule.bgSourceRuleRepo.setRulePinned(
              rule.id,
              !rule.pinned,
            ),
          ),
          Switch(
            value: rule.enabled,
            onChanged: (v) =>
                DbModule.bgSourceRuleRepo.setRuleEnabled(rule.id, v),
          ),
          PopupMenuButton<String>(
            tooltip: '',
            onSelected: (value) {
              switch (value) {
                case 'edit':
                  onEdit();
                case 'duplicate':
                  onDuplicate();
                case 'delete':
                  onDelete();
              }
            },
            itemBuilder: (context) => [
              if (!rule.builtin)
                PopupMenuItem(value: 'edit', child: Text(t.bg_src_edit)),
              PopupMenuItem(value: 'duplicate', child: Text(t.bg_src_duplicate)),
              if (!rule.builtin)
                PopupMenuItem(value: 'delete', child: Text(t.bg_src_delete)),
            ],
          ),
        ],
      ),
    );
  }
}

