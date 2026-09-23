import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/paginated_browser/data_source/paginated_browser_data_source.dart';
import 'package:iris/features/paginated_browser/models/generic_browser_models.dart';
import 'package:iris/features/paginated_browser/paginated_browser_controller.dart';
import 'package:iris/features/paginated_browser/paginated_browser_page.dart';
import 'package:iris/l10n/app_localizations.dart';

/// v15-D5 regression: long-press enters selection mode and the selection
/// SURVIVES rebuilds — the page must hold a stable controller instance
/// (the search page passes one via useMemoized; the page also memoizes its
/// fallback). A fresh controller per build used to wipe the selection state
/// the moment `enterSelectionMode` notified.
class _SelectionDS extends PaginatedBrowserDataSource<String> {
  int _currentPage = 0;
  List<String> _items = const [];

  _SelectionDS() {
    fetchPage(0, 5);
  }

  @override
  int get totalItems => 3;

  @override
  int get currentPage => _currentPage;

  @override
  int get totalPages => 1;

  @override
  int get pageSize => 5;

  @override
  bool get isLoading => false;

  @override
  bool get isError => false;

  @override
  List<String> get items => _items;

  @override
  String getItemId(String item) => item;

  @override
  List<String>? get currentBreadcrumbs => null;

  @override
  bool get isRightToLeftBreadcrumbs => false;

  @override
  Future<void> fetchPage(int targetPage, int currentSize) async {
    _currentPage = targetPage;
    _items = const ['a', 'b', 'c'];
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
  bool get supportsSelection => true;

  @override
  Future<void> openSearchDialog(
      BuildContext context, VoidCallback onSearchInitiated) async {}

  @override
  bool handleItemTap(BuildContext context, String item) => true;

  @override
  Widget buildTileInfoDialog(BuildContext context, String item) =>
      const SizedBox();

  @override
  Widget? buildItemLeading(BuildContext context, String item) => null;

  @override
  String? buildItemTitle(String item) => item;

  @override
  Widget? buildItemSubtitle(BuildContext context, String item) => null;

  @override
  Widget? buildTileContent(BuildContext context, String item) => null;

  @override
  Widget buildSortMenu(BuildContext context) => const SizedBox.shrink();

  @override
  List<PageAction> buildCustomPageActions(BuildContext context) => [];

  @override
  List<CustomSelectionAction<String>> buildCustomSelectionActions(
          BuildContext context) =>
      const [];

  @override
  List<GenericItemAction<String>> getItemTrailingActions(
          BuildContext context, String item) =>
      [];
}

Widget _wrap(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SizedBox(
        width: 800,
        height: 600,
        child: child,
      ),
    ),
  );
}

void main() {
  testWidgets(
      'long-press enters selection mode and the selection survives a rebuild '
      '(v15-D5)', (tester) async {
    final ds = _SelectionDS();
    final controller = PaginatedBrowserController<String>();
    await tester.pumpWidget(_wrap(PaginatedBrowserPage<String>(
      dataSource: ds,
      controller: controller,
      showHomePage: false,
      showBackButton: false,
    )));
    await tester.pumpAndSettle();

    // Long-press a tile → selection mode with the item selected.
    await tester.longPress(find.text('a'));
    await tester.pumpAndSettle();
    expect(controller.isSelectionMode, isTrue);
    expect(controller.selectedIds, contains('a'));

    // Force a rebuild (e.g. the data source refreshing) — the selection MUST
    // persist because the controller instance is stable across rebuilds.
    ds.notifyListeners();
    await tester.pumpAndSettle();
    expect(controller.isSelectionMode, isTrue);
    expect(controller.selectedIds, contains('a'));

    // Toggling a second tile still works on the same controller.
    await tester.tap(find.text('b'));
    await tester.pumpAndSettle();
    expect(controller.selectedIds, containsAll(['a', 'b']));
  });

  testWidgets('selection survives a rebuild even without a passed controller '
      '(page memoizes its fallback)', (tester) async {
    final ds = _SelectionDS();
    await tester.pumpWidget(_wrap(PaginatedBrowserPage<String>(
      dataSource: ds,
      showHomePage: false,
      showBackButton: false,
    )));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('a'));
    await tester.pumpAndSettle();
    ds.notifyListeners();
    await tester.pumpAndSettle();
    // Selection-mode UI (the checkbox leading tile) is still rendered.
    expect(find.byType(Checkbox), findsNWidgets(3));
  });
}
