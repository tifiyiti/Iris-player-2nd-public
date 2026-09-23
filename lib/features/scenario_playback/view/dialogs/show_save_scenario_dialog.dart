import 'package:flutter/material.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/scenario_playback/model/domain/scenario.dart';
import 'package:iris/features/scenario_playback/model/enum/scenario_kind.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';
import 'package:iris/features/scenario_playback/view/dialogs/show_confirm_save_action_dialog.dart';
import 'package:iris/widgets/dialogs/show_copyable_error_dialog.dart';

/// What the user chose in the Save current playing dialog.
enum SaveScenarioAction {
  saveNew,
  syncBack,
  overrideOther,
  appendOther,
  cancel
}

/// Result of the Save current playing dialog.
class SaveScenarioResult {
  final SaveScenarioAction action;
  final String? name;
  final String? description;
  final String? targetScenarioId;

  const SaveScenarioResult({
    required this.action,
    this.name,
    this.description,
    this.targetScenarioId,
  });
}

/// Dialog for "Save current playing as new" / "Sync back to origin" /
/// "Override/Append to a chosen scenario" (D1/D2/E2).
Future<SaveScenarioResult> showSaveScenarioDialog(
  BuildContext context, {
  required Scenario workspace,
}) {
  final store = usePlaybackScenarioStore();
  return store.getState(workspace.id).then((state) {
    if (!context.mounted) {
      return const SaveScenarioResult(action: SaveScenarioAction.cancel);
    }
    final originName = state?.originScenarioId == null
        ? null
        : store.state.scenarios
            .where((s) => s.id == state!.originScenarioId)
            .firstOrNull
            ?.name;
    return showDialog<SaveScenarioResult>(
      context: context,
      builder: (_) => _SaveScenarioDialog(
        workspace: workspace,
        canSyncBack: state?.originScenarioId != null,
        originName: originName,
      ),
    ).then((r) =>
        r ?? const SaveScenarioResult(action: SaveScenarioAction.cancel));
  });
}

/// Executes the chosen save action (E2: sync disabled when no origin).
///
/// Returns true when the action succeeded (the caller should refresh), false
/// otherwise (failure dialog already shown; the caller must NOT refresh).
/// [name]/[description] are the values captured by the save dialog at confirm
/// time (C2) — [SaveScenarioAction.syncBack] forwards them so a missing-origin
/// fallback can save as new with the same field values (D18).
Future<bool> runSaveScenarioAction(
  BuildContext context,
  Scenario workspace, {
  required SaveScenarioAction action,
  String? name,
  String? description,
  String? targetScenarioId,
}) async {
  final store = usePlaybackScenarioStore();
  try {
    switch (action) {
      case SaveScenarioAction.saveNew:
        await store.saveWorkspaceAs(
          workspace,
          name: name?.isNotEmpty == true ? name : null,
          description: description,
        );
      case SaveScenarioAction.syncBack:
        final ok = await store.syncWorkspaceBack(workspace);
        if (!ok) {
          // D18: origin no longer exists → offer to save as new instead.
          if (!context.mounted) return false;
          final proceed = await _showOriginMissingFallback(context);
          if (proceed != true) return false;
          await store.saveWorkspaceAs(
            workspace,
            name: name?.isNotEmpty == true ? name : null,
            description: description,
          );
        }
      case SaveScenarioAction.overrideOther:
        await store.overrideOther(
          workspace: workspace,
          targetScenarioId: targetScenarioId!,
          description: description,
        );
      case SaveScenarioAction.appendOther:
        await store.appendOther(
          workspace: workspace,
          targetScenarioId: targetScenarioId!,
          description: description,
        );
      case SaveScenarioAction.cancel:
        return false;
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      await _showErrorDialog(context, e);
    }
    return false;
  }
}

Future<void> _showErrorDialog(BuildContext context, Object error) async {
  // v15-D6: the uniform copyable error surface.
  await showCopyableErrorDialog(
    context,
    title: getLocalizations(context).scn_save_failed,
    message: '$error',
  );
}

Future<bool> _showOriginMissingFallback(BuildContext context) async {
  final proceed = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final t = getLocalizations(ctx);
      return AlertDialog(
        title: Text(t.scn_origin_missing),
        content: Text(t.scn_origin_missing_body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.scn_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.scn_save_as_new),
          ),
        ],
      );
    },
  );
  return proceed == true;
}

class _SaveScenarioDialog extends HookWidget {
  const _SaveScenarioDialog({
    required this.workspace,
    required this.canSyncBack,
    this.originName,
  });

  final Scenario workspace;
  final bool canSyncBack;
  final String? originName;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final store = usePlaybackScenarioStore();
    // C2 baseline: the prefilled description (also the save-new write value).
    final baseline = useState(_timestamp());
    final nameController =
        useTextEditingController(text: store.nextDefaultScenarioName());
    final descriptionController =
        useTextEditingController(text: baseline.value);
    // Reactive mirror of all scenarios (source of truth), no direct DB read.
    final scenarios =
        usePlaybackScenarioStore().select(context, (s) => s.scenarios);
    final saved = scenarios
        .where((s) => s.type == ScenarioKind.userSaved && s.id != workspace.id)
        .toList();
    final targetId = useState<String?>(null);

    // O1: empty-workspace detection, queried once on open; conservative
    // disable until the query resolves.
    final emptyFuture =
        useMemoized(() => store.isWorkspaceEmpty(workspace.id), [workspace.id]);
    final emptyResult = useFuture(emptyFuture);
    final workspaceEmpty = emptyResult.data ?? true;

    final name = nameController.text.trim();
    final nameDuplicate = saved.any((s) => s.name == name);
    final saveNewDisabled = name.isEmpty || nameDuplicate;
    final actionDisabled = workspaceEmpty;

    /// C2: the value that will be written. Unedited → the prefilled baseline
    /// (save-new) or the click-time template (override/append). Edited → the
    /// user text. Computed ONCE at confirm-push time; preview == write.
    String writeDescription({String? template}) {
      final text = descriptionController.text.trim();
      if (text.isNotEmpty && text != baseline.value) return text;
      return template ?? baseline.value;
    }

    Future<void> saveNew() async {
      Navigator.pop(
        context,
        SaveScenarioResult(
          action: SaveScenarioAction.saveNew,
          name: nameController.text.trim(),
          description: writeDescription(),
        ),
      );
    }

    Future<void> overrideOther() async {
      final target = saved.firstWhere((s) => s.id == targetId.value);
      final desc = writeDescription(
          template:
              '${_timestamp()} ${t.scn_desc_override_suffix}');
      final confirmed = await showSaveConfirmDialog(
        context,
        kind: SaveConfirmKind.override,
        targetName: target.name,
        descriptionEcho: desc,
      );
      if (!context.mounted || !confirmed) return;
      Navigator.pop(
        context,
        SaveScenarioResult(
          action: SaveScenarioAction.overrideOther,
          name: nameController.text.trim(),
          description: desc,
          targetScenarioId: target.id,
        ),
      );
    }

    Future<void> appendOther() async {
      final target = saved.firstWhere((s) => s.id == targetId.value);
      final desc = writeDescription(
          template: '${_timestamp()} ${t.scn_desc_append_suffix}');
      final confirmed = await showSaveConfirmDialog(
        context,
        kind: SaveConfirmKind.append,
        targetName: target.name,
        descriptionEcho: desc,
      );
      if (!context.mounted || !confirmed) return;
      Navigator.pop(
        context,
        SaveScenarioResult(
          action: SaveScenarioAction.appendOther,
          name: nameController.text.trim(),
          description: desc,
          targetScenarioId: target.id,
        ),
      );
    }

    Future<void> syncBack() async {
      final confirmed = await showSaveConfirmDialog(
        context,
        kind: SaveConfirmKind.syncBack,
        targetName: originName ?? t.scn_origin_fallback,
      );
      if (!context.mounted || !confirmed) return;
      Navigator.pop(
        context,
        SaveScenarioResult(
          action: SaveScenarioAction.syncBack,
          name: nameController.text.trim(),
          description: descriptionController.text.trim(),
        ),
      );
    }

    return AlertDialog(
      title: Text(t.scn_save_playing),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: t.scn_name_label,
                hintText: t.scn_name_hint_full,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: descriptionController,
              decoration: InputDecoration(
                labelText: t.scn_desc_label,
                hintText: '${t.scn_desc_hint_prefix}${_timestamp()}',
                hintStyle: const TextStyle(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 12),
            if (canSyncBack)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.sync),
                title: Text(t.scn_sync_origin),
                enabled: !actionDisabled,
                onTap: actionDisabled ? null : syncBack,
              ),
            if (saved.isNotEmpty)
              DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: t.scn_copy_to),
                isExpanded: true,
                items: [
                  for (final s in saved)
                    DropdownMenuItem(
                      value: s.id,
                      child: Text(s.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (id) => targetId.value = id,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context,
              const SaveScenarioResult(action: SaveScenarioAction.cancel)),
          child: Text(t.scn_cancel),
        ),
        if (targetId.value != null) ...[
          TextButton(
            onPressed:
                actionDisabled ? null : () => overrideOther(),
            child: Text(t.scn_override_it),
          ),
          TextButton(
            onPressed:
                actionDisabled ? null : () => appendOther(),
            child: Text(t.scn_append_it),
          ),
        ],
        FilledButton(
          onPressed: saveNewDisabled ? null : saveNew,
          child: Text(t.scn_save_as_new),
        ),
      ],
    );
  }
}

String _timestamp() {
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)} '
      '${two(now.hour)}:${two(now.minute)}';
}
