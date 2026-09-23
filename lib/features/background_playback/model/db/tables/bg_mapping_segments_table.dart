import 'package:drift/drift.dart';
import 'package:iris/features/background_playback/model/db/tables/bg_mappings_table.dart';

/// One timeline segment of a [BgMappingsTable] row (v26).
///
/// Actions: `playMedia` = play the referenced background file over its own
/// range; `silence` = no 副音 (bg fields stay null). Absolute ms values are
/// the source of truth; normalized 0–1 fractions of the media durations are
/// persisted alongside so editor/UI display survives duration drift and can
/// cross-check (a mismatch after re-probe warns instead of silently shifting).
class BgMappingSegmentsTable extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get mappingId => integer().references(
        BgMappingsTable,
        #id,
        onDelete: KeyAction.cascade,
      )();

  /// action: 'playMedia' | 'silence' (plain text on purpose — no drift enum
  /// codegen dependency for a two-value domain).
  TextColumn get action => text()();

  IntColumn get fgStartMs => integer()();
  IntColumn get fgEndMs => integer()();

  RealColumn get fgStartN => real().nullable()();
  RealColumn get fgEndN => real().nullable()();

  TextColumn get bgStorageId => text().nullable()();
  TextColumn get bgPath => text().nullable()();

  IntColumn get bgStartMs => integer().nullable()();
  IntColumn get bgEndMs => integer().nullable()();

  RealColumn get bgStartN => real().nullable()();
  RealColumn get bgEndN => real().nullable()();

  /// Segment-relative alignment rate computed at save (editor review aid).
  RealColumn get adjustedRate => real().nullable()();

  /// Per-segment volume split (v27). NULL = the media/global pair applies.
  /// A 0 [bgPercent] keeps the file but silences the 副音 track for this
  /// segment; a `silence` segment carries no bg file at all.
  IntColumn get fgPercent => integer().nullable()();
  IntColumn get bgPercent => integer().nullable()();

  /// Label colour of this segment on the foreground axis (v32), ARGB.
  /// NULL = no explicit choice; the UI derives a stable colour (see
  /// `segment_color.dart`). Purely cosmetic — never affects playback.
  IntColumn get colorArgb => integer().nullable()();

  /// Whether this segment participates in playback/display (v34). A disabled
  /// segment keeps its data but is invisible to resolution, so the user can
  /// park a mapping without deleting it.
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// Per-foreground activation order (v34). Larger = activated later = the
  /// winner wherever active segments overlap (last-fired-wins). Scoped to the
  /// parent mapping — never compared across foregrounds.
  IntColumn get activeSeq => integer().withDefault(const Constant(0))();

  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
}
