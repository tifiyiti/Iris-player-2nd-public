import 'package:drift/drift.dart';
import 'package:iris/features/media_library/model/enum/media_lib_sources.dart';

/// SQLite INTEGER = signed 64-bit.
///
/// Max:
/// 9,223,372,036,854,775,807 bytes
///
/// ≈ 8 EiB
/// ≈ 9.22 EB
/// ≈ 9.2 million terabytes (TB).
/// More than sufficient for any realistic media library.
class MediaLibSourcesTable extends Table {
  @override
  String get tableName => 'media_lib_sources';

  IntColumn get id => integer().autoIncrement()();

  TextColumn get libraryId => text()();
  TextColumn get storageId => text()();

  TextColumn get path => text().nullable()(); // NULL = full storage
  /// Optional display name (e.g., "Movies_2026-07-27 14:30:00").
  /// Falls back to path.last when null.
  TextColumn get name => text().nullable()();
  /// Depth in directory tree:
  /// 0 = root storage
  /// 1 = Movies
  /// 2 = Movies/Action
  IntColumn get pathDepth => integer().withDefault(const Constant(0))();

  TextColumn get mediaSourceKind => textEnum<MediaSourceKind>().nullable()();

  // Aggregates
  IntColumn get totalMediaCount => integer().withDefault(const Constant(0))();
  IntColumn get totalDirCount => integer().withDefault(const Constant(0))();
  IntColumn get totalItemCount => integer().withDefault(const Constant(0))();
  IntColumn get totalSizeInBytes => integer().withDefault(const Constant(0))();
  IntColumn get totalDurationMs => integer().withDefault(const Constant(0))();
  //
  //
  DateTimeColumn get modifiedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable()();

  @override
  List<String> get customConstraints => ['UNIQUE(library_id, storage_id, path)'];
}
