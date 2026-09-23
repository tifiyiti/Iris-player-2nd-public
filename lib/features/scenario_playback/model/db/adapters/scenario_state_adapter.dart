import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:iris/features/scenario_playback/model/domain/playback_occurrence_id.dart';
import 'package:iris/features/scenario_playback/model/domain/scenario_state.dart';
import 'package:iris/models/db/app_database.dart';

extension ScenarioStateAdapter on ScenarioState {
  static ScenarioState fromDb(ScenarioStatesTableData row) {
    PlaybackOccurrenceId? occurrence;
    final raw = row.currentPlaybackOccurrence;
    if (raw != null && raw.isNotEmpty) {
      try {
        occurrence = PlaybackOccurrenceId.fromJson(json.decode(raw) as Map<String, dynamic>);
      } catch (_) {
        occurrence = null;
      }
    }
    return ScenarioState(
      scenarioId: row.scenarioId,
      currentPlaybackOccurrence: occurrence,
      currentVirtualPos: row.currentVirtualPos,
      shuffleSeed: row.shuffleSeed,
      shuffleVersion: row.shuffleVersion,
      shuffleItemCount: row.shuffleItemCount,
      originScenarioId: row.originScenarioId,
      importedAt: row.importedAt,
      importVersion: row.importVersion,
      lastActiveAt: row.lastActiveAt,
    );
  }

  ScenarioStatesTableCompanion toCompanion() {
    return ScenarioStatesTableCompanion(
      scenarioId: Value(scenarioId),
      currentPlaybackOccurrence: Value(
        currentPlaybackOccurrence == null
            ? null
            : json.encode(currentPlaybackOccurrence!.toJson()),
      ),
      currentVirtualPos: Value(currentVirtualPos),
      shuffleSeed: Value(shuffleSeed),
      shuffleVersion: Value(shuffleVersion),
      shuffleItemCount: Value(shuffleItemCount),
      originScenarioId: Value(originScenarioId),
      importedAt: Value(importedAt),
      importVersion: Value(importVersion),
      lastActiveAt: Value(lastActiveAt),
    );
  }
}
