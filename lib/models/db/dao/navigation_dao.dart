import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/tables/navigation_table.dart';

part 'navigation_dao.g.dart';

@DriftAccessor(tables: [NavigationTable])
class NavigationDao extends DatabaseAccessor<AppDatabase> with _$NavigationDaoMixin {
  NavigationDao(super.db);

  Future<NavigationTableData?> getMain() {
    return (select(navigationTable)..where((t) => t.key.equals('main'))).getSingleOrNull();
  }

  Future<void> saveMain({
    String? currentStorageId,
    List<String>? currentPath,
  }) {
    return into(navigationTable).insertOnConflictUpdate(
      NavigationTableCompanion(
        key: const Value('main'),
        currentStorageId: Value(currentStorageId),
        currentPathJson: Value(
          currentPath == null ? null : json.encode(currentPath),
        ),
      ),
    );
  }
}
