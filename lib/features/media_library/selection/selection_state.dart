import 'package:freezed_annotation/freezed_annotation.dart';

part 'selection_state.freezed.dart';

// part 'selection_state.g.dart';   // Disabled for now

/// ================================================
/// SelectionState<T>
///
/// NOTE: Generic JSON serialization is **temporarily disabled**
/// to avoid upgrading SDK constraint to ^3.8.0+ right now.
///
/// We are using manual fromJson/toJson instead of @JsonSerializable
/// with genericArgumentFactories.
///
/// TODO: Upgrade environment sdk to ^3.8.0 and enable proper
///       json_serializable generic support later.
///       Then uncomment the g.dart part and add:
///       @JsonSerializable(genericArgumentFactories: true)
/// ================================================

@freezed
abstract class SelectionState<T> with _$SelectionState<T> {
  const SelectionState._();

  const factory SelectionState({
    @Default(false) bool active,
    Set<T>? selected,
    T? anchor,
  }) = _SelectionState<T>;

  Set<T> get safeSelected => selected ?? {};

  bool get isSelecting => active;
  int get count => safeSelected.length;
  bool isSelected(T value) => safeSelected.contains(value);

// === MANUAL JSON ===
// not: part 'selection_state.g.dart';
  factory SelectionState.fromJson(
    Map<String, dynamic> json,
    T Function(Object?) fromJsonT,
  ) {
    return SelectionState<T>(
      active: json['active'] as bool? ?? false,
      selected: (json['selected'] as List?)?.map(fromJsonT).toSet() ?? {},
      anchor: json['anchor'] != null ? fromJsonT(json['anchor']) : null,
    );
  }

  Map<String, dynamic> toJson(Object? Function(T) toJsonT) {
    return {
      'active': active,
      'selected': safeSelected.map(toJsonT).toList(),
      'anchor': anchor == null ? null : toJsonT(anchor as T),
    };
  }
}
