import 'package:flutter/material.dart';
import 'package:iris/features/paginated_browser/data_source/paginated_browser_data_source.dart';

class PaginatedBrowserController<T> extends ChangeNotifier {
  final Set<String> selectedIds = {};
  T? anchorItem;
  bool isSelectionMode = false;

  bool isSearchActive = false;
  String activeSearchQuery = '';

  bool isSelected(T item, PaginatedBrowserDataSource<T> dataSource) {
    return selectedIds.contains(dataSource.getItemId(item));
  }

  void enterSelectionMode(T item, PaginatedBrowserDataSource<T> dataSource) {
    isSelectionMode = true;
    selectedIds.clear();
    if (dataSource.isItemSelectable(item)) {
      selectedIds.add(dataSource.getItemId(item));
      anchorItem = item;
    } else {
      anchorItem = null;
    }
    notifyListeners();
  }

  void toggleSelection(T item, PaginatedBrowserDataSource<T> dataSource) {
    if (!dataSource.isItemSelectable(item)) return;
    final id = dataSource.getItemId(item);
    if (selectedIds.contains(id)) {
      selectedIds.remove(id);
    } else {
      selectedIds.add(id);
    }
    anchorItem = item;
    notifyListeners();
  }

  void toggleSelectAllOnPage(List<T> pageItems, PaginatedBrowserDataSource<T> dataSource) {
    final selectable =
        pageItems.where(dataSource.isItemSelectable).toList(growable: false);
    bool allSelected = true;
    for (final item in selectable) {
      if (!selectedIds.contains(dataSource.getItemId(item))) {
        allSelected = false;
        break;
      }
    }

    if (allSelected) {
      for (final item in selectable) {
        selectedIds.remove(dataSource.getItemId(item));
      }
    } else {
      for (final item in selectable) {
        selectedIds.add(dataSource.getItemId(item));
      }
    }
    notifyListeners();
  }

  void invertSelection(List<T> pageItems, PaginatedBrowserDataSource<T> dataSource) {
    for (final item in pageItems) {
      if (!dataSource.isItemSelectable(item)) continue;
      final id = dataSource.getItemId(item);
      if (selectedIds.contains(id)) {
        selectedIds.remove(id);
      } else {
        selectedIds.add(id);
      }
    }
    notifyListeners();
  }

  /// Playlist keyboard `Ctrl+A`: enter selection mode and select every row on
  /// the current page (PotPlayer's Select All within the visible list).
  void selectAllOnPage(
    List<T> pageItems,
    PaginatedBrowserDataSource<T> dataSource,
  ) {
    isSelectionMode = true;
    for (final item in pageItems) {
      if (!dataSource.isItemSelectable(item)) continue;
      selectedIds.add(dataSource.getItemId(item));
    }
    notifyListeners();
  }

  /// Playlist keyboard `Ctrl+J`: enter selection mode and XOR every row on the
  /// current page (PotPlayer's Invert Selection).
  void invertSelectionOnPage(
    List<T> pageItems,
    PaginatedBrowserDataSource<T> dataSource,
  ) {
    isSelectionMode = true;
    for (final item in pageItems) {
      if (!dataSource.isItemSelectable(item)) continue;
      final id = dataSource.getItemId(item);
      if (!selectedIds.remove(id)) selectedIds.add(id);
    }
    notifyListeners();
  }

  void clearSelection() {
    selectedIds.clear();
    anchorItem = null;
    isSelectionMode = false;
    notifyListeners();
  }

  void processRangeXorSelection(
    T targetItem,
    List<T> pageItems,
    PaginatedBrowserDataSource<T> dataSource,
  ) {
    if (!dataSource.isItemSelectable(targetItem)) return;
    final targetId = dataSource.getItemId(targetItem);
    if (anchorItem == null) {
      toggleSelection(targetItem, dataSource);
      return;
    }

    final anchorId = dataSource.getItemId(anchorItem as T);
    final anchorIdx = pageItems.indexWhere((item) => dataSource.getItemId(item) == anchorId);
    final targetIdx = pageItems.indexWhere((item) => dataSource.getItemId(item) == targetId);

    if (anchorIdx == -1 || targetIdx == -1) {
      toggleSelection(targetItem, dataSource);
      return;
    }

    final start = anchorIdx < targetIdx ? anchorIdx + 1 : targetIdx;
    final end = anchorIdx < targetIdx ? targetIdx : anchorIdx - 1;

    for (int i = start; i <= end; i++) {
      final item = pageItems[i];
      if (!dataSource.isItemSelectable(item)) continue;
      final itemId = dataSource.getItemId(item);
      if (selectedIds.contains(itemId)) {
        selectedIds.remove(itemId);
      } else {
        selectedIds.add(itemId);
      }
    }

    anchorItem = targetItem;
    notifyListeners();
  }

  void startSearch(String query) {
    isSearchActive = true;
    activeSearchQuery = query;
    clearSelection(); // Context-Bound Reset
    notifyListeners();
  }

  void cancelSearch() {
    isSearchActive = false;
    activeSearchQuery = '';
    clearSelection(); // Context-Bound Reset
    notifyListeners();
  }
}
