import 'package:drift/drift.dart';

class NavigationTable extends Table {
  TextColumn get key => text()(); // always use 'main'
  TextColumn get currentStorageId => text().nullable()();
  TextColumn get currentPathJson => text().nullable()(); // JSON list

  @override
  Set<Column> get primaryKey => {key};
}
