import 'package:flutter/material.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/paginated_browser/data_source/paginated_browser_data_source.dart';
import 'package:iris/features/paginated_browser/models/generic_browser_models.dart';
import 'package:iris/features/paginated_browser/models/tooltip_direction.dart';
import 'package:iris/features/scenario_playback/model/enum/scenario_queue_profile.dart';
import 'package:iris/store/use_app_store.dart';

/// Minimal in-memory [PaginatedBrowserDataSource] for toolbar-chrome tests.
///
/// The queue's V1/V2 layouts are pure toolbar concerns, so the tests only need a
/// data source that reports a known page/total and hands back the action lists
/// it is given — no DB, no store, no scenario resolver.
class FakePagedBrowserDataSource extends PaginatedBrowserDataSource<String> {
  final List<PageAction> customActions;
  final List<PageAction> trailingActions;
  final List<CustomSelectionAction<String>> selectionActions;
  final List<String>? breadcrumbs;
  final bool supportsCurrent;

  /// Invoked when the sort menu button is tapped (the fake renders a plain
  /// button instead of a real popup).
  final VoidCallback? onSortTapped;

  FakePagedBrowserDataSource({
    this.customActions = const [],
    this.trailingActions = const [],
    this.selectionActions = const [],
    this.breadcrumbs,
    this.supportsCurrent = false,
    this.onSortTapped,
  }) {
    fetchPage(0, pageSizePerPage);
  }

  static const int pageSizePerPage = 5;
  static const int totalItemCount = 10;

  int _currentPage = 0;
  late List<String> _items = [];

  @override
  int get totalItems => totalItemCount;

  @override
  int get currentPage => _currentPage;

  @override
  int get totalPages => totalItemCount ~/ pageSizePerPage;

  @override
  int get pageSize => pageSizePerPage;

  @override
  bool get isLoading => false;

  @override
  bool get isError => false;

  @override
  List<String> get items => _items;

  @override
  String getItemId(String item) => item;

  @override
  List<String>? get currentBreadcrumbs => breadcrumbs;

  @override
  bool get isRightToLeftBreadcrumbs => false;

  @override
  Future<void> fetchPage(int targetPage, int currentSize) async {
    _currentPage = targetPage;
    _items = [for (var i = 0; i < pageSizePerPage; i++) 'item$i'];
    notifyListeners();
  }

  @override
  Future<void> changePageSize(int newSize) async {}

  @override
  Future<void> changeSort(SortOption sortOption) async {}

  @override
  Future<bool> handleNavigationBack() async => false;

  @override
  Future<void> handleNavigationHome() async {}

  @override
  Future<void> navigateToCrumb(int index) async {}

  @override
  bool get supportsSearch => false;

  @override
  Future<void> openSearchDialog(
      BuildContext context, VoidCallback onSearchInitiated) async {}

  @override
  bool handleItemTap(BuildContext context, String item) => true;

  @override
  Widget buildTileInfoDialog(BuildContext context, String item) =>
      const SizedBox.shrink();

  @override
  Widget? buildItemLeading(BuildContext context, String item) => null;

  @override
  String? buildItemTitle(String item) => item;

  @override
  Widget? buildItemSubtitle(BuildContext context, String item) => null;

  @override
  Widget? buildTileContent(BuildContext context, String item) => null;

  @override
  Widget buildSortMenu(BuildContext context) => IconButton(
        icon: const Icon(Icons.sort_rounded),
        onPressed: onSortTapped,
      );

  @override
  List<PageAction> buildCustomPageActions(BuildContext context) {
    // Real data sources (notably the scenario queue) read app state here to
    // decide what to offer, e.g. the queue picks its layout-switch target from
    // the CURRENT screen shape's stored layout. `context.select` is only legal
    // inside a widget build, so a toolbar that assembles these rows lazily —
    // e.g. from a PopupMenuButton's `itemBuilder`, which runs on tap — throws
    // and the menu never opens. Mirrored here so that regression is covered by
    // every test using this fake.
    final profile = scenarioQueueProfileOf(context, state: useAppStore().state);
    useAppStore().select(context, (s) => s.scenarioQueueLayoutFor(profile));
    return customActions;
  }

  @override
  List<PageAction> buildTrailingPageActions(BuildContext context) {
    useAppStore().select(context, (s) => s.playlistPanelMode);
    return trailingActions;
  }

  @override
  List<CustomSelectionAction<String>> buildCustomSelectionActions(
          BuildContext context) =>
      selectionActions;

  @override
  List<GenericItemAction<String>> getItemTrailingActions(
      BuildContext context, String item) =>
      [];

  @override
  bool get supportsCurrentItem => supportsCurrent;

  @override
  TooltipDirection get tooltipDirection => TooltipDirection.above;
}
