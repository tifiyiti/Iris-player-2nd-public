import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/features/background_playback/actions/background_playback_actions.dart';
import 'package:iris/features/background_playback/model/db/repositories/bg_source_rule_repository.dart';
import 'package:iris/features/background_playback/model/source/bg_source_rule.dart';
import 'package:iris/features/background_playback/services/bg_source_staging.dart';
import 'package:iris/features/background_playback/view/bg_source_labels.dart';
import 'package:iris/features/background_playback/view/bg_source_rule_editor.dart';
import 'package:iris/features/background_playback/view/widgets/bg_source_banner.dart';
import 'package:iris/features/tag_play/model/domain/tag_play_tag.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/store/warning_dialogs.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/dialogs/show_confirm_suppressible_dialog.dart';
import 'package:iris/widgets/dialogs/show_message_dialog.dart';

/// Phone/desktop breakpoint for the staged manager shell.
const double kBgSourceManageDialogBreakpoint = 600;

/// Opens the staged 副音 source manager owned by the play-queue button.
///
/// Unlike the settings sheet (which writes immediately), every edit here is
/// buffered until the bottom ✓ is pressed. Presented as a full-screen route on
/// phones and a centred dialog on desktop; both are PUSHED routes, so closing
/// pops only this surface. (A docked panel is not a route — popping the root
/// there would white-screen, so the manager never touches the host.)
Future<void> showBgSourceManage(BuildContext context) async {
  final t = getLocalizations(context);
  // First-use explainer; suppressible and restorable from Settings → Warning
  // dialogs. The helper no-ops once suppressed.
  await showInfoSuppressibleDialog(
    context,
    warningId: kWarningBgSourceManage,
    title: t.dlg_warn_bg_source_manage_title,
    message: t.dlg_warn_bg_source_manage_desc,
    defaultDontAsk: true,
  );
  if (!context.mounted) return;

  final width = MediaQuery.sizeOf(context).width;
  if (width < kBgSourceManageDialogBreakpoint) {
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const Scaffold(
          body: SafeArea(child: BgSourceManageBody()),
        ),
      ),
    );
  } else {
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
          child: const BgSourceManageBody(),
        ),
      ),
    );
  }
}

/// Staged source-rule list body, shared by the phone page and the desktop dialog.
///
/// Reads the rules ONCE (no stream) so the working copy is never clobbered by a
/// concurrent DB write; the DB is touched only when ✓ is pressed.
class BgSourceManageBody extends HookWidget {
  const BgSourceManageBody({super.key, this.repo});

  /// Test seam: overrides the rule repository so load/save failures can be
  /// exercised without a real DB error. Null in prod.
  final BgSourceRuleRepository? repo;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final theme = Theme.of(context);
    final ruleRepo = repo ?? DbModule.bgSourceRuleRepo;

    final working = useState<List<BgSourceRule>?>(null);
    final loadError = useState<Object?>(null);
    final reloadTick = useState(0);
    final original = useRef<List<BgSourceRule>>(const []);
    final tagsFuture = useFuture(
      useMemoized(() => DbModule.tagPlayRepo.tags(), const []),
    );

    useEffect(() {
      var cancelled = false;
      // Reset so a retry shows the spinner again instead of a stale list.
      working.value = null;
      loadError.value = null;
      ruleRepo.loadRules().then((loaded) {
        if (cancelled) return;
        original.value = loaded;
        working.value = sortStagedRules(loaded);
      }).catchError((Object e) {
        if (cancelled) return;
        loadError.value = e;
      });
      return () => cancelled = true;
    }, [reloadTick.value]);

    final tags = tagsFuture.data ?? const <TagPlayTag>[];
    final tagName = {for (final g in tags) g.id: g.name};
    final rules = working.value;
    final enabledCount = rules?.where((r) => r.enabled).length ?? 0;

    void setWorking(List<BgSourceRule> next) {
      // Keep the DAO display order (pinned-first, then sortOrder) on every edit.
      working.value = sortStagedRules(next);
    }

    void toggleEnabled(BgSourceRule rule) => setWorking([
          for (final r in rules!)
            if (r.id == rule.id) r.copyWith(enabled: !r.enabled) else r,
        ]);

    void togglePinned(BgSourceRule rule) => setWorking([
          for (final r in rules!)
            if (r.id == rule.id) r.copyWith(pinned: !r.pinned) else r,
        ]);

    void remove(BgSourceRule rule) {
      if (rule.builtin) return;
      setWorking([for (final r in rules!) if (r.id != rule.id) r]);
    }

    Future<void> addNew() async {
      final created = await openBgSourceRuleEditor(
        context,
        sortOrder: nextStagedSortOrder(rules!),
        persist: false,
      );
      if (created == null || !context.mounted) return;
      setWorking([...rules, created]);
    }

    Future<void> edit(BgSourceRule rule) async {
      final updated = await openBgSourceRuleEditor(
        context,
        initial: rule,
        sortOrder: rule.sortOrder,
        persist: false,
      );
      if (updated == null || !context.mounted) return;
      setWorking([
        for (final r in rules!) if (r.id == updated.id) updated else r,
      ]);
    }

    void duplicate(BgSourceRule rule) => setWorking([
          ...rules!,
          rule.copyWith(
            id: 'bgsrc_${DateTime.now().microsecondsSinceEpoch}',
            name: t.bg_src_copy_name(bgSourceRuleLabel(rule, t)),
            builtin: false,
            enabled: false,
            sortOrder: nextStagedSortOrder(rules),
            createdAt: DateTime.now(),
          ),
        ]);

    void close() {
      if (context.mounted) Navigator.of(context).pop();
    }

    Future<void> confirm() async {
      final navigator = Navigator.of(context, rootNavigator: true);
      final diff =
          diffBgSourceRules(original: original.value, working: rules!);
      try {
        for (final r in diff.toSave) {
          await ruleRepo.saveRule(r);
        }
        for (final id in diff.toDelete) {
          await ruleRepo.deleteRule(id);
        }
      } catch (_) {
        // A failed write leaves the DB partially updated; keep the manager open
        // so the user can retry (save/delete are both idempotent) or discard.
        if (!navigator.mounted) return;
        await showMessageDialog(
          navigator,
          type: MessageDialogType.error,
          title: t.bg_source_manage_title,
          message: t.bg_source_manage_save_failed,
        );
        return;
      }
      // Safety net: the candidate pool normally re-resolves on its own because
      // the rule fingerprint covers every resolution-relevant field this
      // manager edits. Forcing it here also covers the non-fingerprinted case
      // (a name/description-only stage) and keeps the confirm path explicit.
      BackgroundPlaybackActions.invalidateSourceRules();
      close();
    }

    final Widget listBody;
    if (rules == null && loadError.value != null) {
      listBody = Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: theme.colorScheme.error),
              const SizedBox(height: 8),
              Text(
                t.bg_source_manage_load_failed,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => reloadTick.value++,
                child: Text(t.retry),
              ),
            ],
          ),
        ),
      );
    } else if (rules == null) {
      listBody = const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    } else if (rules.isEmpty) {
      listBody = Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            t.bg_sources_empty_hint,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    } else {
      listBody = ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: rules.length,
        itemBuilder: (context, i) {
          final rule = rules[i];
          return _ManageRuleTile(
            rule: rule,
            label: bgSourceRuleLabel(rule, t),
            summary: bgSourceRuleSummary(rule, t, tagName),
            onToggleEnabled: () => toggleEnabled(rule),
            onTogglePinned: () => togglePinned(rule),
            onEdit: () => edit(rule),
            onDuplicate: () => duplicate(rule),
            onDelete: () => remove(rule),
          );
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  t.bg_source_manage_title,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: t.close,
                icon: const Icon(Icons.close),
                onPressed: close,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.set_bg_sources_desc, style: theme.textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(
                t.bg_source_manage_staged_hint,
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        ),
        if (rules != null && enabledCount == 0)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: BgSourceFallbackBanner(),
          ),
        const Divider(height: 1),
        Expanded(child: listBody),
        const Divider(height: 1),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Row(
              children: [
                IconButton(
                  tooltip: t.bg_sources_add,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.add_rounded, size: 20),
                  onPressed: rules == null ? null : addNew,
                ),
                IconButton(
                  tooltip: t.bg_src_refresh_now,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  onPressed: () => BackgroundPlaybackActions.refresh(context),
                ),
                const Spacer(),
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: close,
                  child: Text(t.bg_source_manage_discard),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onPressed: rules == null ? null : confirm,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text(t.bg_source_manage_confirm),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One staged row: leading enable radio, trailing pin + more (edit/duplicate/
/// delete). Tapping the row toggles enable; nothing here writes to the DB.
class _ManageRuleTile extends StatelessWidget {
  const _ManageRuleTile({
    required this.rule,
    required this.label,
    required this.summary,
    required this.onToggleEnabled,
    required this.onTogglePinned,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
  });

  final BgSourceRule rule;
  final String label;
  final String summary;
  final VoidCallback onToggleEnabled;
  final VoidCallback onTogglePinned;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      onTap: onToggleEnabled,
      leading: Icon(
        rule.enabled
            ? Icons.radio_button_checked
            : Icons.radio_button_unchecked,
        size: 20,
        color: rule.enabled
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: rule.enabled
            ? null
            : TextStyle(color: theme.disabledColor),
      ),
      subtitle: Text(
        summary,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall,
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
            onPressed: onTogglePinned,
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
