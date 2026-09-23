import 'package:freezed_annotation/freezed_annotation.dart';

part 'scenario_explicit_item.freezed.dart';
part 'scenario_explicit_item.g.dart';

/// A small user-created addition to a [Scenario] (C4).
///
/// Explicit items are NOT sources. They are manual picks grouped into a batch
/// by [batchId]: one user multi-select operation = one batch of rows sharing
/// the same batchId, ordered by [addOrder], with [uiSortKey] capturing the UI
/// sort value at add time so the as-added order can be replayed later.
///
/// Identity: [mediaId] preferred, else (storageId, path) fallback (A8).
@freezed
abstract class ScenarioExplicitItem with _$ScenarioExplicitItem {
  const factory ScenarioExplicitItem({
    required int id,
    required String scenarioId,
    /// Groups one user operation (multi-select / trailing add-to-queue).
    String? batchId,
    required String storageId,
    required String path,
    /// Future: mediaId-based identity. Prefer when present (A8).
    int? mediaId,
    /// Add-time timeline within the batch.
    @Default(0) int addOrder,
    /// UI sort value at add time (replay as-added order).
    String? uiSortKey,
    DateTime? createdAt,
  }) = _ScenarioExplicitItem;

  factory ScenarioExplicitItem.fromJson(Map<String, dynamic> json) =>
      _$ScenarioExplicitItemFromJson(json);
}
