import 'package:drift/drift.dart';

class MediaLibsTable extends Table {
  @override
  String get tableName => 'media_libs';

  TextColumn get id => text()(); // uuid
  TextColumn get name => text()();

  IntColumn get libType => integer()();
  // 0 = default, 1 = custom

  DateTimeColumn get createdAt => dateTime().nullable()();

  DateTimeColumn get updatedAt => dateTime().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}
