import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:iris/features/background_playback/model/enum/bg_source_rule_kind.dart';
import 'package:iris/features/background_playback/model/enum/bg_source_sort_field.dart';
import 'package:iris/features/media_library/model/enum/basic_enum.dart';
import 'package:iris/utils/dir_match.dart';

part 'bg_source_rule.freezed.dart';

/// One ordered, toggleable 副音 candidate-source rule.
///
/// Persisted in the `bg_source_rules` Drift table (not the store JSON);
/// rows map through `BgSourceRuleRepository`. The built-in 「音库纯 tag 源」
/// carries [builtin] = true and can never be deleted.
///
/// Every rule resolves to real single files only — virtual/merged media is
/// never a candidate.
@freezed
abstract class BgSourceRule with _$BgSourceRule {
  const factory BgSourceRule({
    required String id,
    @Default('') String name,
    @Default('') String description,
    @Default(BgSourceRuleKind.tag) BgSourceRuleKind kind,
    @Default(true) bool enabled,
    @Default(false) bool pinned,
    @Default(false) bool builtin,

    /// tag kind: null = the reserved 「副音备选」system tag.
    int? tagId,

    /// directory kind: 指定/匹配 × 递归/非递归.
    @Default(DirMatchMode.specifiedDir) DirMatchMode matchMode,
    @Default(<String>[]) List<String> paths,
    @Default(<DirPatternEntry>[]) List<DirPatternEntry> patterns,

    /// directory kind: when true, intersect matches with [filterTagId].
    @Default(false) bool tagFilterEnabled,
    int? filterTagId,

    /// file kind: one explicit file.
    String? fileStorageId,
    String? filePath,

    @Default(BgSourceSortField.tagAddedAt) BgSourceSortField sortField,
    @Default(SortDirection.desc) SortDirection sortDirection,
    @Default(0) int sortOrder,
    DateTime? createdAt,
  }) = _BgSourceRule;
}
