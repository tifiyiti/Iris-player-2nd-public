import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/paginated_browser/data_source/paginated_browser_data_source.dart';
import 'package:iris/features/paginated_browser/models/generic_browser_models.dart';
import 'package:iris/features/paginated_browser/paginated_browser_controller.dart';
import 'package:iris/features/paginated_browser/paginated_browser_page.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/enums/storage_list_error.dart';

/// Minimal data source locked in the load-failed state.
class _ErrorDS extends PaginatedBrowserDataSource<String> {
  _ErrorDS(this._kind, this._detail);

  final StorageListErrorKind? _kind;
  final String? _detail;

  @override
  int get totalItems => 0;
  @override
  int get currentPage => 0;
  @override
  int get totalPages => 1;
  @override
  int get pageSize => 50;
  @override
  bool get isLoading => false;
  @override
  bool get isError => true;
  @override
  StorageListErrorKind? get listErrorKind => _kind;
  @override
  String? get listErrorDetail => _detail;
  @override
  List<String> get items => const <String>[];
  @override
  String getItemId(String item) => item;
  @override
  List<String>? get currentBreadcrumbs => null;
  @override
  bool get isRightToLeftBreadcrumbs => false;

  @override
  Future<void> fetchPage(int targetPage, int currentSize) async {}
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
  List<PageAction> buildCustomPageActions(BuildContext context) => [];
  @override
  List<CustomSelectionAction<String>> buildCustomSelectionActions(
          BuildContext context) =>
      [];
  @override
  List<GenericItemAction<String>> getItemTrailingActions(
          BuildContext context, String item) =>
      [];
}

Widget _wrap(Widget child) => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(width: 800, height: 600, child: child),
      ),
    );

Future<void> _pump(WidgetTester tester, PaginatedBrowserDataSource<String> ds) async {
  await tester.pumpWidget(_wrap(PaginatedBrowserPage<String>(
    dataSource: ds,
    controller: PaginatedBrowserController<String>(),
    onClose: () {},
    showHomePage: false,
    showBackButton: false,
  )));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('explains why the listing failed instead of showing "no items"',
      (tester) async {
    await _pump(
      tester,
      _ErrorDS(
        StorageListErrorKind.httpBlocked,
        'Insecure HTTP is not allowed by platform: http://192.168.1.4:5005/',
      ),
    );

    expect(find.text('Failed to load browser contents.'), findsOneWidget);
    expect(
      find.text(
          'The platform blocked plaintext HTTP — use https, or allow cleartext for this host.'),
      findsOneWidget,
    );

    final detail = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(detail.data, contains('Insecure HTTP is not allowed by platform'));

    // A failure must never be presented as an empty directory.
    expect(find.text('No items found.'), findsNothing);
  });

  testWidgets('maps each classification to its own explanation', (tester) async {
    await _pump(
      tester,
      _ErrorDS(StorageListErrorKind.unauthorized, 'HTTP 401'),
    );
    expect(
      find.text('The server rejected the username or password (401/403).'),
      findsOneWidget,
    );
  });

  testWidgets('falls back to a generic reason when unclassified',
      (tester) async {
    await _pump(tester, _ErrorDS(null, null));

    expect(find.text('Failed to read the directory.'), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);
  });
}
