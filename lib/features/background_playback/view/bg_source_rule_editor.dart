import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/features/background_playback/model/enum/bg_source_rule_kind.dart';
import 'package:iris/features/background_playback/model/enum/bg_source_sort_field.dart';
import 'package:iris/features/background_playback/model/source/bg_source_rule.dart';
import 'package:iris/features/media_library/model/enum/basic_enum.dart';
import 'package:iris/features/tag_play/model/domain/tag_play_tag.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/store/use_storage_store.dart';
import 'package:iris/utils/dir_match.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/utils/path_conv.dart';
import 'package:iris/utils/platform.dart';
import 'package:iris/widgets/adaptive/keyboard_inset_padder.dart';
import 'package:saf_util/saf_util.dart';

final _log = AreaKeyLog(LogKeys.legacyDb);

/// Phone/desktop breakpoint for the editor shell (dialog vs bottom sheet).
const double kBgEditorSheetBreakpoint = 600;

/// Opens the adaptive 副音 source-rule editor.
///
/// Phone ⇒ bottom sheet, desktop ⇒ centred dialog; both share ONE cached form
/// and a single keyboard padder (see [BgSourceRuleEditorForm]).
///
/// Returns the edited rule on save, or null when cancelled. With [persist]
/// (the default) the rule is written to the repository before returning; pass
/// `persist: false` to let a staging caller collect it without touching the DB.
///
/// The `default*` parameters prefill a NEW draft only (`initial == null`);
/// editing an existing rule ignores them and keeps its stored values.
Future<BgSourceRule?> openBgSourceRuleEditor(
  BuildContext context, {
  BgSourceRule? initial,
  required int sortOrder,
  bool persist = true,
  String? defaultName,
  String? defaultDescription,
  BgSourceRuleKind? defaultKind,
  DirMatchMode? defaultMatchMode,
  List<String>? defaultPaths,
  String? defaultFileStorageId,
  String? defaultFilePath,
}) async {
  final width = MediaQuery.sizeOf(context).width;
  final Future<BgSourceRule?> saved;
  if (width < kBgEditorSheetBreakpoint) {
    saved = showModalBottomSheet<BgSourceRule>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => BgSourceRuleEditorSheet(
        initial: initial,
        sortOrder: sortOrder,
        persist: persist,
        defaultName: defaultName,
        defaultDescription: defaultDescription,
        defaultKind: defaultKind,
        defaultMatchMode: defaultMatchMode,
        defaultPaths: defaultPaths,
        defaultFileStorageId: defaultFileStorageId,
        defaultFilePath: defaultFilePath,
      ),
    );
  } else {
    saved = showDialog<BgSourceRule>(
      context: context,
      builder: (_) => BgSourceRuleEditorDialog(
        initial: initial,
        sortOrder: sortOrder,
        persist: persist,
        defaultName: defaultName,
        defaultDescription: defaultDescription,
        defaultKind: defaultKind,
        defaultMatchMode: defaultMatchMode,
        defaultPaths: defaultPaths,
        defaultFileStorageId: defaultFileStorageId,
        defaultFilePath: defaultFilePath,
      ),
    );
  }
  return saved;
}

/// Default values for a folder-scoped NEW source rule (the media-browser
/// trailing quick-add). Pure so it can be unit-tested.
({String name, String description, DirMatchMode matchMode, List<String> paths})
    folderSourceRuleDefaults({
  required String storageName,
  required String folderName,
  required String folderPath,
}) {
  final trimmed = folderName.trim();
  return (
    name: trimmed.isEmpty ? storageName : '$storageName - $trimmed',
    description: _formatTimestamp(DateTime.now()),
    matchMode: DirMatchMode.specifiedDirRecursive,
    paths: <String>[folderPath],
  );
}

/// Quick-add entry for the media browsers: opens the 副音 source-rule editor
/// prefilled to treat [folderPath] (storage-relative, `''` = storage root) as a
/// recursive specified-directory source. Returns the saved rule or null.
Future<BgSourceRule?> openBgSourceRuleEditorForFolder(
  BuildContext context, {
  required String storageName,
  required String folderName,
  required String folderPath,
}) async {
  final defaults = folderSourceRuleDefaults(
    storageName: storageName,
    folderName: folderName,
    folderPath: folderPath,
  );
  final sortOrder = await DbModule.bgSourceRuleRepo.nextSortOrder();
  if (!context.mounted) return null;
  return openBgSourceRuleEditor(
    context,
    sortOrder: sortOrder,
    defaultName: defaults.name,
    defaultDescription: defaults.description,
    defaultKind: BgSourceRuleKind.directory,
    defaultMatchMode: defaults.matchMode,
    defaultPaths: defaults.paths,
  );
}

/// Desktop shell: centred dialog, height-capped.
class BgSourceRuleEditorDialog extends StatefulWidget {
  const BgSourceRuleEditorDialog({
    super.key,
    this.initial,
    required this.sortOrder,
    this.persist = true,
    this.defaultName,
    this.defaultDescription,
    this.defaultKind,
    this.defaultMatchMode,
    this.defaultPaths,
    this.defaultFileStorageId,
    this.defaultFilePath,
  });

  final BgSourceRule? initial;
  final int sortOrder;
  final bool persist;
  final String? defaultName;
  final String? defaultDescription;
  final BgSourceRuleKind? defaultKind;
  final DirMatchMode? defaultMatchMode;
  final List<String>? defaultPaths;
  final String? defaultFileStorageId;
  final String? defaultFilePath;

  @override
  State<BgSourceRuleEditorDialog> createState() =>
      _BgSourceRuleEditorDialogState();
}

class _BgSourceRuleEditorDialogState extends State<BgSourceRuleEditorDialog> {
  // Built EXACTLY ONCE: keyboard frames below never rebuild the form.
  late final Widget _form = BgSourceRuleEditorForm(
    initial: widget.initial,
    sortOrder: widget.sortOrder,
    persist: widget.persist,
    defaultName: widget.defaultName,
    defaultDescription: widget.defaultDescription,
    defaultKind: widget.defaultKind,
    defaultMatchMode: widget.defaultMatchMode,
    defaultPaths: widget.defaultPaths,
    defaultFileStorageId: widget.defaultFileStorageId,
    defaultFilePath: widget.defaultFilePath,
  );

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: size.width < kBgEditorSheetBreakpoint
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 12)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: size.height * 0.92,
        ),
        child: KeyboardInsetPadder(child: _form),
      ),
    );
  }
}

/// Phone shell: bottom sheet, drag handle, scroll-controlled.
class BgSourceRuleEditorSheet extends StatefulWidget {
  const BgSourceRuleEditorSheet({
    super.key,
    this.initial,
    required this.sortOrder,
    this.persist = true,
    this.defaultName,
    this.defaultDescription,
    this.defaultKind,
    this.defaultMatchMode,
    this.defaultPaths,
    this.defaultFileStorageId,
    this.defaultFilePath,
  });

  final BgSourceRule? initial;
  final int sortOrder;
  final bool persist;
  final String? defaultName;
  final String? defaultDescription;
  final BgSourceRuleKind? defaultKind;
  final DirMatchMode? defaultMatchMode;
  final List<String>? defaultPaths;
  final String? defaultFileStorageId;
  final String? defaultFilePath;

  @override
  State<BgSourceRuleEditorSheet> createState() =>
      _BgSourceRuleEditorSheetState();
}

class _BgSourceRuleEditorSheetState extends State<BgSourceRuleEditorSheet> {
  late final Widget _form = BgSourceRuleEditorForm(
    initial: widget.initial,
    sortOrder: widget.sortOrder,
    persist: widget.persist,
    defaultName: widget.defaultName,
    defaultDescription: widget.defaultDescription,
    defaultKind: widget.defaultKind,
    defaultMatchMode: widget.defaultMatchMode,
    defaultPaths: widget.defaultPaths,
    defaultFileStorageId: widget.defaultFileStorageId,
    defaultFilePath: widget.defaultFilePath,
  );

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: size.height * 0.9),
      child: KeyboardInsetPadder(child: _form),
    );
  }
}

/// The heavy form. Reads NO `MediaQuery` (width via `LayoutBuilder`, theme via
/// `Theme`) so keyboard frames cannot rebuild a field.
class BgSourceRuleEditorForm extends HookWidget {
  const BgSourceRuleEditorForm({
    super.key,
    this.initial,
    required this.sortOrder,
    this.persist = true,
    this.defaultName,
    this.defaultDescription,
    this.defaultKind,
    this.defaultMatchMode,
    this.defaultPaths,
    this.defaultFileStorageId,
    this.defaultFilePath,
  });

  /// Test seam: called once per form build (keyboard-frame tests assert 0
  /// rebuilds after the first frame).
  static void Function()? debugOnFormBuild;

  final BgSourceRule? initial;
  final int sortOrder;

  /// When true the form writes the rule before popping; a staging caller passes
  /// false to receive the built rule and persist it itself.
  final bool persist;

  /// Prefill for NEW drafts only (`initial == null`); a non-empty
  /// [defaultName] wins over the timestamp default.
  final String? defaultName;
  final String? defaultDescription;
  final BgSourceRuleKind? defaultKind;
  final DirMatchMode? defaultMatchMode;
  final List<String>? defaultPaths;
  final String? defaultFileStorageId;
  final String? defaultFilePath;

  @override
  Widget build(BuildContext context) {
    debugOnFormBuild?.call();
    final t = getLocalizations(context);
    final r = initial;

    final nameCtrl =
        useTextEditingController(text: r?.name ?? defaultName ?? '');
    final descCtrl = useTextEditingController(
      text: r?.description.isNotEmpty == true
          ? r!.description
          : (defaultDescription ?? _formatTimestamp(DateTime.now())),
    );
    final storageCtrl = useTextEditingController(
      text: r?.fileStorageId ?? defaultFileStorageId ?? '',
    );
    final filePathCtrl =
        useTextEditingController(text: r?.filePath ?? defaultFilePath ?? '');
    final pathInputCtrl = useTextEditingController();

    final kind = useState(r?.kind ?? defaultKind ?? BgSourceRuleKind.tag);
    final matchMode = useState(
      r?.matchMode ?? defaultMatchMode ?? DirMatchMode.specifiedDir,
    );
    final paths = useState<List<String>>(
      List.of(r?.paths ?? defaultPaths ?? const []),
    );
    final patterns =
        useState<List<DirPatternEntry>>(List.of(r?.patterns ?? const []));
    final tagId = useState<int?>(r?.tagId);
    final tagFilterEnabled = useState(r?.tagFilterEnabled ?? false);
    final filterTagId = useState<int?>(r?.filterTagId);
    final sortField = useState(r?.sortField ?? BgSourceSortField.tagAddedAt);
    final sortDirection = useState(r?.sortDirection ?? SortDirection.desc);
    final enabled = useState(r?.enabled ?? true);

    final tagsFuture = useFuture(
      useMemoized(() => DbModule.tagPlayRepo.tags(), const []),
    );
    final tags = tagsFuture.data ?? const <TagPlayTag>[];

    // Dropdown items for the tag pickers. A saved rule may reference a tag that
    // has since been deleted: the live list no longer contains it, and
    // `DropdownButtonFormField` asserts (red-screens) when its value is not
    // among the items. Keep a placeholder for a stale id so the editor still
    // opens and the user can re-pick.
    List<DropdownMenuItem<int>> tagItems(int? selected) => [
          for (final g in tags)
            DropdownMenuItem(value: g.id, child: Text(g.name)),
          if (selected != null && !tags.any((g) => g.id == selected))
            DropdownMenuItem(value: selected, child: Text('#$selected')),
        ];

    bool isPattern() =>
        matchMode.value == DirMatchMode.patternDir ||
        matchMode.value == DirMatchMode.patternDirRecursive;

    bool valid() {
      switch (kind.value) {
        case BgSourceRuleKind.tag:
          return tagId.value != null;
        case BgSourceRuleKind.directory:
          if (isPattern()) {
            return patterns.value
                .any((p) => p.activated && p.text.trim().isNotEmpty);
          }
          return paths.value.isNotEmpty;
        case BgSourceRuleKind.file:
          return storageCtrl.text.trim().isNotEmpty &&
              filePathCtrl.text.trim().isNotEmpty;
      }
    }

    Future<void> save() async {
      if (!valid()) return;
      final isDir = kind.value == BgSourceRuleKind.directory;
      final rule = BgSourceRule(
        id: r?.id ?? 'bgsrc_${DateTime.now().microsecondsSinceEpoch}',
        name: nameCtrl.text.trim(),
        description: descCtrl.text.trim(),
        kind: kind.value,
        enabled: enabled.value,
        pinned: r?.pinned ?? false,
        builtin: r?.builtin ?? false,
        tagId: kind.value == BgSourceRuleKind.tag ? tagId.value : null,
        matchMode: matchMode.value,
        paths: isDir ? paths.value : const [],
        patterns: isDir ? patterns.value : const [],
        tagFilterEnabled:
            isDir ? tagFilterEnabled.value : false,
        filterTagId: isDir && tagFilterEnabled.value ? filterTagId.value : null,
        fileStorageId:
            kind.value == BgSourceRuleKind.file ? storageCtrl.text.trim() : null,
        filePath:
            kind.value == BgSourceRuleKind.file ? filePathCtrl.text.trim() : null,
        sortField: sortField.value,
        sortDirection: sortDirection.value,
        sortOrder: r?.sortOrder ?? sortOrder,
        createdAt: r?.createdAt ?? DateTime.now(),
      );
      if (persist) {
        await DbModule.bgSourceRuleRepo.saveRule(rule);
      }
      if (context.mounted) Navigator.of(context).pop(rule);
    }

    Future<void> pickDirectory() async {
      String? raw;
      try {
        if (isAndroid) {
          final dir = await SafUtil().pickDirectory();
          raw = dir?.uri;
        } else {
          raw = await FilePicker.platform.getDirectoryPath();
        }
      } catch (e) {
        _log.w('bg source path pick failed: $e');
      }
      final rel = raw == null ? '' : _relativeToLibrary(raw);
      if (rel.isNotEmpty) paths.value = [...paths.value, rel];
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Sticky header.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  r == null ? t.bg_src_new_rule : t.bg_src_edit_rule,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 420;
              return SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        labelText: t.vm_editor_name,
                        border: const OutlineInputBorder(),
                      ),
                      autofocus: !isMobilePlatform,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descCtrl,
                      decoration: InputDecoration(
                        labelText: t.bg_src_field_description,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    _label(context, t.bg_src_field_kind),
                    SegmentedButton<BgSourceRuleKind>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                          value: BgSourceRuleKind.tag,
                          label: Text(t.bg_src_kind_tag),
                        ),
                        ButtonSegment(
                          value: BgSourceRuleKind.directory,
                          label: Text(t.bg_src_kind_directory),
                        ),
                        ButtonSegment(
                          value: BgSourceRuleKind.file,
                          label: Text(t.bg_src_kind_file),
                        ),
                      ],
                      selected: {kind.value},
                      onSelectionChanged: (s) => kind.value = s.first,
                    ),
                    const SizedBox(height: 8),
                    if (tagsFuture.hasError)
                      Text(t.bg_sources_tags_error)
                    else ...[
                      if (kind.value == BgSourceRuleKind.tag)
                        DropdownButtonFormField<int>(
                          key: const ValueKey('bg_src_tag_pick'),
                          initialValue: tagId.value,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: t.bg_src_field_tag,
                            border: const OutlineInputBorder(),
                          ),
                          items: tagItems(tagId.value),
                          onChanged: (v) => tagId.value = v,
                        ),
                      if (kind.value == BgSourceRuleKind.directory) ...[
                        DropdownButtonFormField<DirMatchMode>(
                          key: const ValueKey('bg_src_match_mode'),
                          initialValue: matchMode.value,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: t.vm_editor_match_mode,
                            border: const OutlineInputBorder(),
                          ),
                          items: [
                            for (final m in DirMatchMode.values)
                              DropdownMenuItem(
                                value: m,
                                child: Text(_modeLabel(m, t)),
                              ),
                          ],
                          onChanged: (v) =>
                              matchMode.value = v ?? matchMode.value,
                        ),
                        if (isPattern())
                          _PatternsSection(
                            t: t,
                            patterns: patterns.value,
                            onChanged: (next) => patterns.value = next,
                          )
                        else
                          _PathsSection(
                            t: t,
                            paths: paths.value,
                            narrow: narrow,
                            inputCtrl: pathInputCtrl,
                            onPick: pickDirectory,
                            onChanged: (next) => paths.value = next,
                          ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(t.bg_src_field_tag_filter),
                          value: tagFilterEnabled.value,
                          onChanged: (v) => tagFilterEnabled.value = v,
                        ),
                        if (tagFilterEnabled.value)
                          DropdownButtonFormField<int>(
                            key: const ValueKey('bg_src_filter_tag_pick'),
                            initialValue: filterTagId.value,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: t.bg_src_field_filter_tag,
                              border: const OutlineInputBorder(),
                            ),
                            items: tagItems(filterTagId.value),
                            onChanged: (v) => filterTagId.value = v,
                          ),
                      ],
                      if (kind.value == BgSourceRuleKind.file) ...[
                        TextField(
                          controller: storageCtrl,
                          decoration: InputDecoration(
                            labelText: t.bg_src_field_storage,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: filePathCtrl,
                          decoration: InputDecoration(
                            labelText: t.bg_src_field_path,
                            hintText: t.bg_src_field_path_hint,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ],
                    _label(context, t.bg_src_field_sort),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<BgSourceSortField>(
                            initialValue: sortField.value,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              for (final f in BgSourceSortField.values)
                                DropdownMenuItem(
                                  value: f,
                                  child: Text(_sortLabel(f, t)),
                                ),
                            ],
                            onChanged: (v) =>
                                sortField.value = v ?? sortField.value,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<SortDirection>(
                            initialValue: sortDirection.value,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              DropdownMenuItem(
                                value: SortDirection.asc,
                                child: Text(t.vm_editor_sort_asc),
                              ),
                              DropdownMenuItem(
                                value: SortDirection.desc,
                                child: Text(t.vm_editor_sort_desc),
                              ),
                            ],
                            onChanged: (v) =>
                                sortDirection.value = v ?? sortDirection.value,
                          ),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(t.bg_src_enabled),
                      value: enabled.value,
                      onChanged: (v) => enabled.value = v,
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              );
            },
          ),
        ),
        // Sticky footer.
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(t.vm_editor_cancel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Builder(
                  builder: (context) => FilledButton(
                    // Rebuild the button state on field changes.
                    onPressed: valid() ? save : null,
                    child: Text(t.vm_editor_save),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PathsSection extends StatelessWidget {
  const _PathsSection({
    required this.t,
    required this.paths,
    required this.narrow,
    required this.inputCtrl,
    required this.onPick,
    required this.onChanged,
  });

  final AppLocalizations t;
  final List<String> paths;
  final bool narrow;
  final TextEditingController inputCtrl;
  final Future<void> Function() onPick;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(context, t.vm_editor_match_mode),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.folder_open, size: 18),
              label: Text(t.bg_src_pick_dir),
            ),
            SizedBox(
              width: narrow ? 160 : 240,
              child: TextField(
                controller: inputCtrl,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: t.vm_editor_paste_path,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (v) {
                  final rel = _relativeToLibrary(v);
                  if (rel.isNotEmpty) {
                    onChanged([...paths, rel]);
                    inputCtrl.clear();
                  }
                },
              ),
            ),
            IconButton(
              tooltip: t.vm_editor_tooltip_add,
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () {
                final rel = _relativeToLibrary(inputCtrl.text);
                if (rel.isEmpty) return;
                onChanged([...paths, rel]);
                inputCtrl.clear();
              },
            ),
          ],
        ),
        if (paths.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              t.vm_sheet_no_conditions,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        else
          for (var i = 0; i < paths.length; i++)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.folder_outlined, size: 18),
              title: Text(
                paths[i].isEmpty ? t.vm_editor_library_root : paths[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                tooltip: t.vm_editor_tooltip_remove,
                icon: const Icon(Icons.remove_circle_outline, size: 18),
                onPressed: () => onChanged(
                  [...paths]..removeAt(i),
                ),
              ),
            ),
      ],
    );
  }
}

class _PatternsSection extends StatelessWidget {
  const _PatternsSection({
    required this.t,
    required this.patterns,
    required this.onChanged,
  });

  final AppLocalizations t;
  final List<DirPatternEntry> patterns;
  final ValueChanged<List<DirPatternEntry>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(context, t.vm_editor_match_mode),
        for (var i = 0; i < patterns.length; i++)
          _PatternRow(
            t: t,
            entry: patterns[i],
            onChanged: (next) => onChanged(
              [...patterns]..[i] = next,
            ),
            onRemove: () => onChanged([...patterns]..removeAt(i)),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: Text(t.vm_editor_add_condition),
            onPressed: () => onChanged([
              ...patterns,
              const DirPatternEntry(kind: DirPatternKind.contains),
            ]),
          ),
        ),
      ],
    );
  }
}

class _PatternRow extends StatelessWidget {
  const _PatternRow({
    required this.t,
    required this.entry,
    required this.onChanged,
    required this.onRemove,
  });

  final AppLocalizations t;
  final DirPatternEntry entry;
  final ValueChanged<DirPatternEntry> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 120,
                child: DropdownButtonFormField<DirPatternKind>(
                  initialValue: entry.kind,
                  isDense: true,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final k in DirPatternKind.values)
                      DropdownMenuItem(
                        value: k,
                        child: Text(_patternKindLabel(k, t)),
                      ),
                  ],
                  onChanged: (v) =>
                      onChanged(entry.copyWith(kind: v ?? entry.kind)),
                ),
              ),
              FilterChip(
                label: Text(
                  entry.activated
                      ? t.vm_editor_pattern_active
                      : t.vm_editor_pattern_inactive,
                ),
                selected: entry.activated,
                onSelected: (v) => onChanged(entry.copyWith(activated: v)),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: t.vm_editor_pattern_pin,
                icon: Icon(
                  entry.pinned
                      ? Icons.push_pin
                      : Icons.push_pin_outlined,
                  size: 18,
                ),
                onPressed: () => onChanged(entry.copyWith(pinned: !entry.pinned)),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: t.vm_editor_tooltip_remove,
                icon: const Icon(Icons.remove_circle_outline, size: 18),
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: entry.text,
            decoration: InputDecoration(
              isDense: true,
              hintText: t.vm_editor_pattern_hint,
              border: const OutlineInputBorder(),
            ),
            onChanged: (v) => onChanged(entry.copyWith(text: v)),
          ),
        ],
      ),
    );
  }
}

Widget _label(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );

String _patternKindLabel(DirPatternKind kind, AppLocalizations t) =>
    switch (kind) {
      DirPatternKind.prefix => t.vm_editor_pattern_prefix,
      DirPatternKind.suffix => t.vm_editor_pattern_suffix,
      DirPatternKind.contains => t.vm_editor_pattern_contains,
      DirPatternKind.regex => t.vm_editor_pattern_regex,
    };

String _modeLabel(DirMatchMode mode, AppLocalizations t) => switch (mode) {
      DirMatchMode.specifiedDir => t.vm_editor_match_specified,
      DirMatchMode.specifiedDirRecursive =>
        t.vm_editor_match_specified_recursive,
      DirMatchMode.patternDir => t.vm_editor_match_pattern,
      DirMatchMode.patternDirRecursive => t.vm_editor_match_pattern_recursive,
    };

String _sortLabel(BgSourceSortField field, AppLocalizations t) => switch (field) {
      BgSourceSortField.tagAddedAt => t.bg_src_sort_tag_added,
      BgSourceSortField.name => t.bg_src_sort_name,
      BgSourceSortField.path => t.bg_src_sort_path,
      BgSourceSortField.duration => t.bg_src_sort_duration,
      BgSourceSortField.modifiedAt => t.bg_src_sort_modified,
      BgSourceSortField.size => t.bg_src_sort_size,
    };

String _formatTimestamp(DateTime dt) {
  String two(int v) => v < 10 ? '0$v' : '$v';
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
      '${two(dt.hour)}:${two(dt.minute)}';
}

/// Strips a registered storage base path (and SAF noise) off a picked
/// directory, yielding the storage-relative form rules are stored in.
String _relativeToLibrary(String raw) {
  var s = raw.trim().replaceAll('\\', '/');
  if (s.isEmpty) return '';
  for (final storage in useStorageStore().state.storages) {
    final base = storage.basePath
        .join('/')
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'^file:///'), '');
    if (base.isEmpty) continue;
    if (s.toLowerCase().startsWith(base.toLowerCase())) {
      s = s.substring(base.length);
      break;
    }
  }
  s = s.replaceAll(RegExp(r'^/+'), '').replaceAll(RegExp(r'/+$'), '');
  if (isSafPath(s)) return safReadableRelative(s) ?? s;
  return s;
}
