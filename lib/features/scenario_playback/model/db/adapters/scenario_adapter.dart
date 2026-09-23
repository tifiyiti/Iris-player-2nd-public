import 'package:drift/drift.dart';
import 'package:iris/features/media_library/model/enum/basic_enum.dart';
import 'package:iris/features/scenario_playback/model/domain/scenario.dart';
import 'package:iris/features/scenario_playback/model/enum/duplicate_policy.dart';
import 'package:iris/features/scenario_playback/model/enum/playback_order.dart';
import 'package:iris/features/scenario_playback/model/enum/scenario_kind.dart';
import 'package:iris/features/scenario_playback/model/enum/scenario_sort_field.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/store/app_state.dart' show Repeat;

extension ScenarioAdapter on Scenario {
  static Scenario fromDb(ScenariosTableData row) {
    // Legacy `addedAt` rows (pre-removal) decode as null via drift's textEnum;
    // fallback to name so the queue stays readable without a DB migration.
    return Scenario(
      id: row.id,
      name: row.name,
      description: row.description,
      type: row.type ?? ScenarioKind.userSaved,
      version: row.version,
      sortField: row.sortField ?? ScenarioSortField.name,
      sortDirection: row.sortDirection ?? SortDirection.asc,
      originalSortField: row.originalSortField,
      order: row.order ?? PlaybackOrder.sequential,
      duplicatePolicy: row.duplicatePolicy ?? DuplicatePolicy.allowDuplicate,
      repeatMode: row.repeatMode ?? Repeat.none,
      sourceInternalFirst: row.sourceInternalFirst,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  ScenariosTableCompanion toCompanion() {
    return ScenariosTableCompanion(
      id: Value(id),
      name: Value(name),
      description: Value(description),
      type: Value(type),
      version: Value(version),
      sortField: Value(sortField),
      sortDirection: Value(sortDirection),
      originalSortField: Value(originalSortField),
      order: Value(order),
      duplicatePolicy: Value(duplicatePolicy),
      repeatMode: Value(repeatMode),
      sourceInternalFirst: Value(sourceInternalFirst),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }
}
