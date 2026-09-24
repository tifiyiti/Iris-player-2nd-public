import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/features/tag_play/model/domain/tag_play_pin_preset.dart';
import 'package:iris/features/tag_play/store/use_tag_play_store.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/utils/get_localizations.dart';

/// Pin-preset management ("激活套装"): save the CURRENT global pin order as a
/// named preset, apply a preset, or delete presets. Unlimited entries.
Future<void> showPinPresetDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (_) => const _PinPresetDialog(),
  );
}

class _PinPresetDialog extends HookWidget {
  const _PinPresetDialog();

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final repo = DbModule.tagPlayRepo;
    final store = useTagPlayStore();
    final presets = useState<List<TagPlayPinPreset>?>(null);
    final nameCtrl = useTextEditingController();

    Future<void> refresh() async {
      presets.value = await repo.presets();
    }

    useEffect(() {
      refresh();
      return null;
    }, const []);

    final list = presets.value ?? const <TagPlayPinPreset>[];

    return AlertDialog(
      title: Text(t.tag_pin_title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: nameCtrl,
                    decoration:
                        InputDecoration(labelText: t.tag_pin_name_label),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    await repo.savePreset(TagPlayPinPreset(
                      id: 0,
                      name: name,
                      pinnedTagIds: List.of(store.state.pinnedTagIds),
                    ));
                    nameCtrl.clear();
                    await refresh();
                  },
                  child: Text(t.tag_pin_save_current),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(t.tag_pin_empty),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final preset in list)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.push_pin_outlined),
                            title: Text(preset.name),
                            subtitle: Text(t.tag_pin_count(
                                preset.pinnedTagIds.length)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton(
                                  onPressed: () async {
                                    await store.setPinnedOrder(
                                        List.of(preset.pinnedTagIds));
                                  },
                                  child: Text(t.tag_pin_apply),
                                ),
                                IconButton(
                                  tooltip: t.tag_delete_tip,
                                  icon: Icon(Icons.delete_outline,
                                      size: 20,
                                      color:
                                          Theme.of(context).colorScheme.error),
                                  onPressed: () async {
                                    await repo.deletePreset(preset.id);
                                    await refresh();
                                  },
                                ),
                              ],
                            ),
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
