import 'package:flutter/material.dart';
import 'package:iris/features/tag_play/model/domain/tag_play_tag.dart';
import 'package:iris/features/tag_play/view/widgets/tag_time_cells_input.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/utils/get_localizations.dart';

/// Default custom-duration used when a fresh policy is switched off "永久".
const Duration kTagRetentionDefault = Duration(hours: 6);
const Duration kTagResumeDefault = Duration(minutes: 30);

/// Create-tag dialog (sheet bottom "+ 新建 Tag"): name + description + both
/// per-tag policies (retention / jump-back window).
Future<void> showCreateTagDialog(BuildContext context) async {
  final nameCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  Duration? retention;
  Duration? resumeWindow;
  var valid = false;

  final result = await showDialog<(String, String, Duration?, Duration?)>(
    context: context,
    builder: (ctx) {
      final t = getLocalizations(ctx);
      return StatefulBuilder(
        builder: (ctx, setState) {
          void revalidate() {
            setState(() => valid = nameCtrl.text.trim().isNotEmpty);
          }

          return AlertDialog(
            title: Text(t.tag_new),
            content: SizedBox(
              width: 340,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      autofocus: true,
                      maxLength: 100,
                      onChanged: (_) => revalidate(),
                      decoration: InputDecoration(
                        labelText: t.tag_name_label,
                        hintText: t.tag_name_hint,
                      ),
                    ),
                    TextField(
                      controller: descCtrl,
                      maxLength: 200,
                      decoration: InputDecoration(
                        labelText: t.tag_desc_label,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(t.tag_retention_label,
                          style: Theme.of(ctx).textTheme.labelLarge),
                    ),
                    TagTimeCellsInput(
                      initial: retention,
                      fallback: kTagRetentionDefault,
                      onChanged: (v) => setState(() => retention = v),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(t.tag_resume_label,
                          style: Theme.of(ctx).textTheme.labelLarge),
                    ),
                    TagTimeCellsInput(
                      initial: resumeWindow,
                      fallback: kTagResumeDefault,
                      onChanged: (v) => setState(() => resumeWindow = v),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(t.tag_cancel),
              ),
              FilledButton(
                onPressed: valid
                    ? () => Navigator.pop(
                        ctx,
                        (
                          nameCtrl.text.trim(),
                          descCtrl.text.trim(),
                          retention,
                          resumeWindow,
                        ))
                    : null,
                child: Text(t.tag_create),
              ),
            ],
          );
        },
      );
    },
  );

  if (result == null) return;
  await DbModule.tagPlayRepo.createTag(
    name: result.$1,
    description: result.$2,
    retention: result.$3,
    resumeWindow: result.$4,
  );
}

/// Edit dialog: rename + description + retention + jump-back window.
///
/// System-reserved tags ([TagPlayTag.systemKind] != null) can only change
/// their description: the name field is read-only and the policy cells are
/// locked to their canonical values.
Future<void> showEditTagDialog(BuildContext context, TagPlayTag tag) async {
  final nameCtrl = TextEditingController(text: tag.name);
  final descCtrl = TextEditingController(text: tag.description);
  var retention = tag.retention;
  var resumeWindow = tag.resumeWindow;
  final reserved = tag.systemKind != null;
  var valid = tag.name.isNotEmpty;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final t = getLocalizations(ctx);
      return StatefulBuilder(
        builder: (ctx, setState) {
          void revalidate() =>
              setState(() => valid = nameCtrl.text.trim().isNotEmpty);

          Widget policyInput(Duration? value, ValueChanged<Duration?> onChanged) {
            return IgnorePointer(
              ignoring: reserved,
              child: Opacity(
                opacity: reserved ? 0.6 : 1,
                child: TagTimeCellsInput(
                  initial: value,
                  fallback: kTagRetentionDefault,
                  onChanged: onChanged,
                ),
              ),
            );
          }

          return AlertDialog(
            title: Text(t.tag_edit_title(tag.name)),
            content: SizedBox(
              width: 360,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (reserved) ...[
                      Text(
                        t.tag_system_reserved,
                        style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
                              color: Theme.of(ctx).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    TextField(
                      controller: nameCtrl,
                      maxLength: 100,
                      readOnly: reserved,
                      onChanged: (_) => revalidate(),
                      decoration: InputDecoration(
                        labelText: t.tag_name_label,
                        helperText: reserved ? t.tag_system_cannot_delete : null,
                      ),
                    ),
                    TextField(
                      controller: descCtrl,
                      maxLength: 200,
                      decoration: InputDecoration(labelText: t.tag_desc_short),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(t.tag_retention_label,
                          style: Theme.of(ctx).textTheme.labelLarge),
                    ),
                    policyInput(retention, (v) => setState(() => retention = v)),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(t.tag_resume_label,
                          style: Theme.of(ctx).textTheme.labelLarge),
                    ),
                    policyInput(
                        resumeWindow, (v) => setState(() => resumeWindow = v)),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(t.tag_cancel),
              ),
              FilledButton(
                onPressed: valid ? () => Navigator.pop(ctx, true) : null,
                child: Text(t.tag_save),
              ),
            ],
          );
        },
      );
    },
  );

  if (confirmed != true) return;
  await DbModule.tagPlayRepo.updateTag(tag.copyWith(
    name: reserved ? tag.name : nameCtrl.text.trim(),
    description: descCtrl.text.trim(),
    retention: reserved ? tag.retention : retention,
    resumeWindow: reserved ? tag.resumeWindow : resumeWindow,
  ));
}
