import 'package:drift/drift.dart';
import 'package:iris/features/background_playback/model/enum/bg_source_rule_kind.dart';
import 'package:iris/features/background_playback/model/enum/bg_source_sort_field.dart';
import 'package:iris/features/media_library/model/enum/basic_enum.dart';
import 'package:iris/utils/dir_match.dart';

/// One 副音 candidate-source rule (v28).
///
/// Rules are DATA: the resolver interprets them, nothing about matching is
/// hard-coded into playback code. Identity is the text [id].
///
/// JSON-in-text columns: [paths] and [patterns] are decoded defensively by
/// [BgSourceRuleRepository] (malformed → default, never throws).
///
/// Display order is pinned-first then [sortOrder] — pin is presentational,
/// the resolver honors list order top-to-bottom.
class BgSourceRulesTable extends Table {
  @override
  String get tableName => 'bg_source_rules';

  /// Stable rule identity (`bgsrc_<micros>`, or the fixed built-in id).
  TextColumn get id => text()();

  /// Display name; empty ⇒ the UI shows the localized built-in name.
  TextColumn get name => text().withDefault(const Constant(''))();

  /// Optional description; empty ⇒ the UI shows the created-at default.
  TextColumn get description => text().withDefault(const Constant(''))();

  TextColumn get kind => textEnum<BgSourceRuleKind>()
      .withDefault(const Constant('tag'))();

  /// Disabled rules are ignored by the resolver entirely.
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  /// Pinned rules display first — presentation only.
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();

  /// Built-in rules cannot be deleted (nor demoted to non-builtin).
  BoolColumn get builtin => boolean().withDefault(const Constant(false))();

  // ── tag kind ──
  /// Tag row id; null = the reserved 「副音备选」system tag.
  IntColumn get tagId => integer().nullable()();

  // ── directory kind ──
  TextColumn get matchMode => textEnum<DirMatchMode>()
      .withDefault(const Constant('specifiedDir'))();

  /// JSON array of picked directory paths (指定模式).
  TextColumn get paths => text().withDefault(const Constant('[]'))();

  /// JSON array of `{kind,text,activated,pinned}` entries (匹配模式).
  TextColumn get patterns => text().withDefault(const Constant('[]'))();

  /// When true, directory matches are intersected with [filterTagId] members.
  BoolColumn get tagFilterEnabled =>
      boolean().withDefault(const Constant(false))();

  IntColumn get filterTagId => integer().nullable()();

  // ── file kind ──
  TextColumn get fileStorageId => text().nullable()();
  TextColumn get filePath => text().nullable()();

  // ── ordering ──
  TextColumn get sortField => textEnum<BgSourceSortField>()
      .withDefault(const Constant('tagAddedAt'))();

  TextColumn get sortDirection =>
      textEnum<SortDirection>().withDefault(const Constant('desc'))();

  /// Insertion timeline within the rules list (max+1, never reused).
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
