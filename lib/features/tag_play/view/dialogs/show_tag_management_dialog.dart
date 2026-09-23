import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/features/scenario_playback/playback/playback_provider_registry.dart';
import 'package:iris/features/tag_play/model/domain/tag_play_tag.dart';
import 'package:iris/features/tag_play/store/use_tag_play_store.dart';
import 'package:iris/features/tag_play/view/dialogs/show_create_tag_dialog.dart'
    show showEditTagDialog;
import 'package:iris/models/db/db_module.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/dialogs/show_message_dialog.dart';

/// Tag management dialog — mirrors the media-library management pattern
/// (list + per-row edit/delete + delete confirmation), per the tag_play spec.
Future<void> showTagManagementDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (_) => const _TagManagementDialog(),
  );
}

class _TagManagementDialog extends HookWidget {
  const _TagManagementDialog();

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final repo = DbModule.tagPlayRepo;
    final tags = useState<List<TagPlayTag>?>(null);

    Future<void> refresh() async {
      tags.value = await repo.tags();
    }

    useEffect(() {
      refresh();
      return null;
    }, const []);

    final list = tags.value ?? const <TagPlayTag>[];

    return AlertDialog(
      title: Text(t.tag_manage_title),
      content: SizedBox(
        width: 420,
        height: 420,
        child: list.isEmpty
            ? Center(child: Text(t.tag_empty))
            : ListView(
                children: [
                  for (final tag in list)
                    ListTile(
                      dense: true,
                      title: Text(tag.name),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (tag.systemKind != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                t.tag_system_reserved,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          if (tag.description.isNotEmpty)
                            Text(tag.description,
                                overflow: TextOverflow.ellipsis),
                          Text(
                            tag.retention == null
                                ? t.tag_retention_forever
                                : t.tag_retention_auto(
                                    tag.retention!.inMinutes),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: t.tag_edit_tip,
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            onPressed: () async {
                              await showEditTagDialog(context, tag);
                              await refresh();
                            },
                          ),
                          if (tag.systemKind != null)
                            IconButton(
                              tooltip: t.tag_system_cannot_delete,
                              icon: Icon(Icons.lock_outline,
                                  size: 20,
                                  color: Theme.of(context).colorScheme.outline),
                              onPressed: () {
                                final t2 = getLocalizations(context);
                                showMessageDialog(
                                  Navigator.of(context, rootNavigator: true),
                                  title: t2.tag_system_reserved,
                                  message: t2.tag_system_cannot_delete,
                                );
                              },
                            )
                          else
                            IconButton(
                              tooltip: t.tag_delete_tip,
                              icon: Icon(Icons.delete_outline,
                                  size: 20, color: Theme.of(context).colorScheme.error),
                              onPressed: () async {
                                final navigator =
                                    Navigator.of(context, rootNavigator: true);
                                final ok = await _confirmDelete(context, tag.name);
                                if (ok != true) return;
                                // Leave the view BEFORE deleting: exiting
                                // captures the tag's live bookmark, and doing
                                // it first avoids flushing progress back onto a
                                // row that was already cascade-deleted.
                                final tp = useTagPlayStore();
                                final wasActive =
                                    tp.state.activeViewTagId == tag.id;
                                if (wasActive) {
                                  await PlaybackProviderRegistry.tagPlay
                                      .exitToNoTag();
                                }
                                await repo.deleteTagCascade(tag.id);
                                // Drop pin references to the deleted tag so the
                                // sheet never dangles.
                                if (tp.state.pinnedTagIds.contains(tag.id)) {
                                  await tp.togglePin(tag.id);
                                }
                                if (!navigator.mounted) return;
                                await refresh();
                              },
                            ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.tag_close),
        ),
      ],
    );
  }
}

Future<bool?> _confirmDelete(BuildContext context, String name) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) {
      final t = getLocalizations(ctx);
      return AlertDialog(
        title: Text(t.tag_delete_title),
        content: Text(t.tag_delete_body(name)),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.tag_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.tag_delete_confirm),
          ),
        ],
      );
    },
  );
}
