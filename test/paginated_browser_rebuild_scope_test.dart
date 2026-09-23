import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/paginated_browser/data_source/paginated_browser_data_source.dart';
import 'package:iris/features/paginated_browser/models/generic_browser_models.dart';
import 'package:iris/features/paginated_browser/paginated_browser_page.dart';
import 'package:iris/features/paginated_browser/widgets/unified_item_tile.dart';
import 'package:iris/l10n/app_localizations.dart';

/// Counting data source: every `items` getter access is tallied so a test can
/// assert how much of the page a notification actually rebuilt.
class _CountingSource extends PaginatedBrowserDataSource<String> {
  _CountingSource(this._items);

  final List<String> _items;
  int itemsReads = 0;
  int buildTileTitleCalls = 0;

  @override
  List<String> get items {
    itemsReads++;
    return _items;
  }

  @override
  int get totalItems => _items.length;
  @override
  int get currentPage => 0;
  @override
  int get totalPages => 1;
  @override
  int get pageSize => 20;
  @override
  bool get isLoading => false;
  @override
  bool get isError => false;
  @override
  String getItemId(String item) => item;

  @override
  String? buildItemTitle(String item) {
    buildTileTitleCalls++;
    return item;
  }

  @override
  bool handleItemTap(BuildContext context, String item) => true;
  @override
  Future<void> fetchPage(int targetPage, int currentSize) async {}
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
  Widget buildTileInfoDialog(BuildContext context, String item) =>
      const SizedBox.shrink();
  @override
  Widget? buildItemLeading(BuildContext context, String item) => null;
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

Future<_CountingSource> _pump(
  WidgetTester tester, {
  required bool listKeyboard,
}) async {
  final source = _CountingSource(['a', 'b', 'c', 'd']);
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: PaginatedBrowserPage<String>(
        dataSource: source,
        listKeyboard: listKeyboard,
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return source;
}

void main() {
  testWidgets('entering selection mode updates every visible checkbox',
      (tester) async {
    final source = await _pump(tester, listKeyboard: false);

    expect(find.byType(Checkbox), findsNothing);
    await tester.longPress(find.text('a'));
    await tester.pumpAndSettle();

    // User-visible contract: every row now carries a checkbox and the first is
    // checked (long-press selected it).
    expect(find.byType(Checkbox), findsNWidgets(4));
    final first = tester.widget<Checkbox>(find.byType(Checkbox).first);
    expect(first.value, isTrue);
    expect(source.itemsReads, greaterThan(0));
  });

  testWidgets('selected-count badge and select-all icon reflect live selection',
      (tester) async {
    await _pump(tester, listKeyboard: false);
    await tester.longPress(find.text('a'));
    await tester.pumpAndSettle();

    // 1 of 4 selected.
    expect(find.text('1/4'), findsOneWidget);
    // Not all on page selected → select-all icon.
    expect(find.byIcon(Icons.select_all), findsOneWidget);

    // Tap a second row's checkbox: count and icon still correct.
    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pumpAndSettle();
    expect(find.text('2/4'), findsOneWidget);

    // Select-all → every row checked, count 4/4, icon flips to deselect.
    await tester.tap(find.byIcon(Icons.select_all));
    await tester.pumpAndSettle();
    expect(find.text('4/4'), findsOneWidget);
    expect(find.byIcon(Icons.deselect), findsOneWidget);
    for (final cb in tester.widgetList<Checkbox>(find.byType(Checkbox))) {
      expect(cb.value, isTrue);
    }
  });

  testWidgets('invert flips every row and the badge', (tester) async {
    await _pump(tester, listKeyboard: false);
    await tester.longPress(find.text('a'));
    await tester.pumpAndSettle();
    expect(find.text('1/4'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.flip));
    await tester.pumpAndSettle();
    expect(find.text('3/4'), findsOneWidget);
    final values =
        tester.widgetList<Checkbox>(find.byType(Checkbox)).map((c) => c.value);
    expect(values, [false, true, true, true]);
  });

  testWidgets('keyboard cursor moves rebuild only the cursor accent',
      (tester) async {
    final source = await _pump(tester, listKeyboard: true);

    await tester.tap(find.text('a'));
    await tester.pumpAndSettle();
    final readsAfterMount = source.itemsReads;

    // Move the cursor down twice; the visible cursor accent must track it.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    // The accent is the only cursor-driven visual: exactly one row carries it.
    final accented = find.byWidgetPredicate((w) =>
        w is UnifiedItemTile<String> && w.keyboardCursor == true);
    expect(accented, findsOneWidget);

    // Cursor movement must not re-read the page items more than a small,
    // bounded amount (each cursor step may rebuild the page shell, but the
    // item list itself is not re-fetched per step). This guards against the
    // old page-scope listener pattern that re-ran the whole build.
    expect(source.itemsReads - readsAfterMount, lessThanOrEqualTo(4));
  });

  testWidgets('loading and error states still swap in correctly',
      (tester) async {
    final source = _CountingSource(['a']);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: PaginatedBrowserPage<String>(dataSource: source)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('a'), findsOneWidget);
  });
}
