import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/paginated_browser/data_source/paginated_browser_data_source.dart';
import 'package:iris/features/paginated_browser/models/generic_browser_models.dart';
import 'package:iris/features/paginated_browser/paginated_browser_page.dart';
import 'package:iris/l10n/app_localizations.dart';

/// Minimal multi-page source: `fetchPage` re-slices the index space and
/// notifies, exactly like the real surfaces do.
class _FakePagedSource extends PaginatedBrowserDataSource<String> {
  _FakePagedSource({required this.totalItems, required this.pageSize});

  @override
  final int totalItems;

  @override
  final int pageSize;

  int _currentPage = 0;
  List<String> _items = const [];

  @override
  int get currentPage => _currentPage;

  @override
  int get totalPages => (totalItems / pageSize).ceil().clamp(1, 99999);

  @override
  bool get isLoading => false;
  @override
  bool get isError => false;

  @override
  List<String> get items => _items;

  @override
  String getItemId(String item) => item;

  @override
  Future<void> fetchPage(int targetPage, int currentSize) async {
    _currentPage = targetPage;
    final start = targetPage * currentSize;
    final end = (start + currentSize).clamp(0, totalItems);
    _items = [for (var i = start; i < end; i++) 'item$i'];
    notifyListeners();
  }

  @override
  Future<void> changePageSize(int newSize) async {}
  @override
  Future<void> changeSort(SortOption sortOption) async {}
  @override
  Future<bool> handleNavigationBack() async => true;
  @override
  Future<void> handleNavigationHome() async {}
  @override
  Future<void> navigateToCrumb(int index) async {}
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
  Widget buildSortMenu(BuildContext context) => const SizedBox.shrink();
  @override
  List<PageAction> buildCustomPageActions(BuildContext context) => const [];
  @override
  List<CustomSelectionAction<String>> buildCustomSelectionActions(
          BuildContext context) =>
      const [];
  @override
  List<GenericItemAction<String>> getItemTrailingActions(
          BuildContext context, String item) =>
      const [];
  @override
  List<String>? get currentBreadcrumbs => null;
  @override
  bool get isRightToLeftBreadcrumbs => false;
}

Widget _wrap(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SizedBox(width: 800, height: 600, child: child),
    ),
  );
}

IconButton _iconButton(WidgetTester tester, IconData icon) {
  return tester.widget<IconButton>(
    find.ancestor(
      of: find.byIcon(icon),
      matching: find.byType(IconButton),
    ),
  );
}

void main() {
  testWidgets(
      'prev/next update the page counter and the button enablement '
      '(dataSource notifications reach the bottom bar)', (tester) async {
    final source = _FakePagedSource(totalItems: 30, pageSize: 5);
    await source.fetchPage(0, source.pageSize);

    await tester.pumpWidget(_wrap(PaginatedBrowserPage<String>(
      dataSource: source,
      showHomePage: false,
      showBackButton: false,
    )));
    await tester.pumpAndSettle();

    // Page 1 of 6, first row visible, and back is disabled at the boundary.
    expect(find.text('1/6'), findsOneWidget);
    expect(find.text('item0'), findsOneWidget);
    expect(_iconButton(tester, Icons.navigate_before).onPressed, isNull);

    // Next → the counter, the list AND the previous button must all react.
    await tester.tap(find.byIcon(Icons.navigate_next));
    await tester.pumpAndSettle();
    expect(find.text('2/6'), findsOneWidget);
    expect(find.text('item5'), findsOneWidget);
    expect(find.text('item0'), findsNothing);
    expect(_iconButton(tester, Icons.navigate_before).onPressed, isNotNull);

    // Back → page 1 again.
    await tester.tap(find.byIcon(Icons.navigate_before));
    await tester.pumpAndSettle();
    expect(find.text('1/6'), findsOneWidget);
    expect(find.text('item0'), findsOneWidget);

    // Last page: next must be disabled (computed from the live page).
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byIcon(Icons.navigate_next));
      await tester.pumpAndSettle();
    }
    expect(find.text('6/6'), findsOneWidget);
    expect(_iconButton(tester, Icons.navigate_next).onPressed, isNull);
  });
}
