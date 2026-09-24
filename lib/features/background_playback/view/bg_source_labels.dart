import 'package:flutter/material.dart';
import 'package:iris/features/background_playback/model/enum/bg_source_rule_kind.dart';
import 'package:iris/features/background_playback/model/source/bg_source_rule.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/utils/dir_match.dart';

/// Shared presentation helpers for 副音 source rules.
///
/// Used by both the immediate settings sheet (`background_sources_sheet.dart`)
/// and the staged queue manager (`bg_source_manage_page.dart`) so the two
/// surfaces label identical rules identically.
IconData bgSourceKindIcon(BgSourceRuleKind kind) => switch (kind) {
      BgSourceRuleKind.tag => Icons.sell_outlined,
      BgSourceRuleKind.directory => Icons.folder_outlined,
      BgSourceRuleKind.file => Icons.insert_drive_file_outlined,
    };

String bgSourceRuleLabel(BgSourceRule rule, AppLocalizations t) {
  if (rule.builtin) return t.bg_src_builtin_name;
  if (rule.name.isNotEmpty) return rule.name;
  return switch (rule.kind) {
    BgSourceRuleKind.tag => t.bg_src_kind_tag,
    BgSourceRuleKind.directory => t.bg_src_kind_directory,
    BgSourceRuleKind.file => t.bg_src_kind_file,
  };
}

String bgSourceRuleSummary(
  BgSourceRule rule,
  AppLocalizations t,
  Map<int, String> tagName,
) {
  switch (rule.kind) {
    case BgSourceRuleKind.tag:
      final label = rule.tagId == null
          ? t.bg_src_builtin_name
          : (tagName[rule.tagId!] ?? '#${rule.tagId}');
      return t.bg_src_summary_tag(label);
    case BgSourceRuleKind.directory:
      final mode = bgSourceMatchModeLabel(rule.matchMode, t);
      final scope = rule.paths.isNotEmpty
          ? (rule.paths.length == 1
              ? rule.paths.first
              : t.bg_src_dir_count(rule.paths.length))
          : t.bg_src_pattern_count(
              rule.patterns.where((p) => p.activated).length,
            );
      if (rule.tagFilterEnabled) {
        final label = rule.filterTagId == null
            ? ''
            : (tagName[rule.filterTagId!] ?? '#${rule.filterTagId}');
        return t.bg_src_summary_dir_tag(mode, scope, label);
      }
      return t.bg_src_summary_dir(mode, scope);
    case BgSourceRuleKind.file:
      final path = rule.filePath ?? '';
      return t.bg_src_summary_file(path);
  }
}

String bgSourceMatchModeLabel(DirMatchMode mode, AppLocalizations t) =>
    switch (mode) {
      DirMatchMode.specifiedDir => t.vm_editor_match_specified,
      DirMatchMode.specifiedDirRecursive =>
        t.vm_editor_match_specified_recursive,
      DirMatchMode.patternDir => t.vm_editor_match_pattern,
      DirMatchMode.patternDirRecursive => t.vm_editor_match_pattern_recursive,
    };
