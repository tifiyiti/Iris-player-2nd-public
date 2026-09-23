import 'dart:convert';

import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/dao/navigation_dao.dart';

class NavigationState {
  final String? currentStorageId;
  final List<String>? currentPath;

  NavigationState({
    this.currentStorageId,
    this.currentPath,
  });

  factory NavigationState.fromRow(NavigationTableData row) {
    return NavigationState(
      currentStorageId: row.currentStorageId,
      currentPath:
          row.currentPathJson == null ? null : List<String>.from(json.decode(row.currentPathJson!)),
    );
  }
}

class NavigationDbRepository {
  final NavigationDao dao;

  NavigationDbRepository(this.dao);

  Future<NavigationState?> getNavigation() async {
    final row = await dao.getMain();
    return row == null ? null : NavigationState.fromRow(row);
  }

  Future<void> saveNavigation({
    String? currentStorageId,
    List<String>? currentPath,
  }) {
    return dao.saveMain(
      currentStorageId: currentStorageId,
      currentPath: currentPath,
    );
  }
}
