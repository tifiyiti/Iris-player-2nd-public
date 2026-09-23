import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/paginated_browser/data_source/paginated_browser_data_source.dart';
import 'package:iris/features/paginated_browser/models/generic_browser_models.dart';
import 'package:iris/features/paginated_browser/models/tooltip_direction.dart';
import 'package:iris/features/paginated_browser/paginated_browser_controller.dart';
import 'package:iris/features/paginated_browser/paginated_browser_page.dart';
import 'package:iris/l10n/app_localizations.dart';

/// Part C: the dock/float toggle of the scenario queue must render as the
/// RIGHTMOST toolbar action (just left of the close X), not inside the
/// mid-bar custom action cluster.
class _FakePagedDS extends PaginatedBrowserDataSource<String> {
  final List<PageAction> trailingActions;

  _FakePagedDS({this.trailingActions = const []}) {
    fetchPage(0, 5);
  }

  int _currentPage = 0;
  List<String> _items = [];

  @override
  int get totalItems => 10;

  @override
  int get currentPage => _currentPage;

  @override
  int get totalPages => 2;

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
    _items = [for (var i = 0; i < 5; i++) 'item$i'];
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
  List<PageAction> buildCustomPageActions(BuildContext context) => [
        PageAction(
          icon: const Icon(Icons.star),
          label: 'custom-a',
          onPressed: () {},
        ),
      ];

  @override
  List<PageAction> buildTrailingPageActions(BuildContext context) =>
      trailingActions;

  @override
  List<CustomSelectionAction<String>> buildCustomSelectionActions(
          BuildContext context) =>
      [];

  @override
  List<GenericItemAction<String>> getItemTrailingActions(
          BuildContext context, String item) =>
      [];

  @override
  TooltipDirection get tooltipDirection => TooltipDirection.above;
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
  testWidgets('trailing actions render right of custom actions, left of close',
      (tester) async {
    final ds = _FakePagedDS(trailingActions: [
      PageAction(
        icon: const Icon(Icons.bookmark),
        label: 'trailing-toggle',
        onPressed: () {},
      ),
    ]);
    await tester.pumpWidget(_wrap(PaginatedBrowserPage<String>(
      dataSource: ds,
      controller: PaginatedBrowserController<String>(),
      onClose: () {},
      showHomePage: false,
      showBackButton: false,
    )));
    await tester.pumpAndSettle();

    final custom = find.byIcon(Icons.star);
    final trailing = find.byIcon(Icons.bookmark);
    final close = find.byIcon(Icons.close);

    expect(custom, findsOneWidget);
    expect(trailing, findsOneWidget);
    expect(close, findsOneWidget);

    final customX = tester.getTopLeft(custom).dx;
    final trailingX = tester.getTopLeft(trailing).dx;
    final closeX = tester.getTopLeft(close).dx;

    expect(trailingX, greaterThan(customX),
        reason: 'trailing toggle must sit at the far right, after every '
            'mid-bar custom action');
    expect(trailingX, lessThan(closeX),
        reason: 'trailing toggle must sit left of the close X');
  });

  testWidgets('no trailing actions -> bar unchanged', (tester) async {
    final ds = _FakePagedDS();
    await tester.pumpWidget(_wrap(PaginatedBrowserPage<String>(
      dataSource: ds,
      controller: PaginatedBrowserController<String>(),
      onClose: () {},
      showHomePage: false,
      showBackButton: false,
    )));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.bookmark), findsNothing);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });
}
