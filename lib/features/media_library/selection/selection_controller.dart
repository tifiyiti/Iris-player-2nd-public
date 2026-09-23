import 'package:flutter/cupertino.dart';
import 'package:iris/features/media_library/selection/selection_state.dart';

class SelectionController<T> extends ChangeNotifier {
  SelectionController({
    required this.isSelectable,
    SelectionState<T>? initialState,
  }) : _state = initialState ?? const SelectionState();

  final bool Function(T value) isSelectable;
  SelectionState<T> _state;

  SelectionState<T> get state => _state;
  bool get isSelecting => _state.isSelecting;
  Set<T> get selected => _state.safeSelected;

  bool isSelected(T value) => _state.isSelected(value);
  int get count => _state.count;

  void _update(SelectionState<T> newState) {
    _state = newState;
    notifyListeners();
  }

  // Core actions
  void enterSelection(T item) {
    if (!isSelectable(item)) return;
    _update(_state.copyWith(
      active: true,
      selected: {item},
      anchor: item,
    ));
  }

  void toggle(T item) {
    if (!isSelectable(item)) return;
    final newSet = {..._state.safeSelected};
    if (newSet.contains(item)) {
      newSet.remove(item);
    } else {
      newSet.add(item);
    }
    _update(_state.copyWith(
      active: true,
      selected: newSet,
      anchor: item,
    ));
  }

  void selectAll(List<T> all) {
    _update(_state.copyWith(
      active: true,
      selected: all.where(isSelectable).toSet(),
    ));
  }

  void clear() {
    _update(_state.copyWith(selected: {}, anchor: null));
  }

  void invertAll(List<T> all) {
    final newSet = all.where(isSelectable).where((e) => !_state.safeSelected.contains(e)).toSet();
    _update(_state.copyWith(active: true, selected: newSet));
  }

  void exit() {
    clear();
    _update(_state.copyWith(
      active: false,
    ));
  }

  void longPressAt(T item, List<T> allItems) {
    if (!isSelectable(item)) return;

    if (!_state.isSelecting) {
      enterSelection(item);
    } else {
      _rangeXor(item, allItems);
    }
  }

  void _rangeXor(T target, List<T> items) {
    if (_state.anchor == null) {
      toggle(target);
      return;
    }

    final start = items.indexOf(_state.anchor as T);
    final end = items.indexOf(target);
    if (start == -1 || end == -1) {
      toggle(target);
      return;
    }

    final min = start < end ? start : end;
    final max = start > end ? start : end;

    final newSet = {..._state.safeSelected};
    for (int i = min; i <= max; i++) {
      if (i == start) {
        continue;
      }
      final v = items[i];
      if (newSet.contains(v)) {
        newSet.remove(v);
      } else {
        newSet.add(v);
      }
    }

    _update(_state.copyWith(
      selected: newSet,
      anchor: target,
    ));
  }
}
