import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/paginated_browser/data_source/paginated_browser_data_source.dart';
import 'package:iris/features/paginated_browser/models/generic_browser_models.dart';
import 'package:iris/features/paginated_browser/paginated_browser_page.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// Fake source exposing the generic expansion hooks over a list long enough to
/// reproduce the `ScrollablePositionedList` centered-anchor case (the current
/// item is centered, so an expandable row sits ABOVE the anchor).
class _ExpandableSource extends PaginatedBrowserDataSource<String> {
  _ExpandableSource(this._items);

  final List<String> _items;
  final int currentIndex = 10;
  final Set<String> expandable = {'item-9'};
  final Set<String> expanded = {};
  int toggleCount = 0;

  @override
  List<String> get items => _items;
  @override
  int get totalItems => _items.length;
  @override
  int get currentPage => 0;
  @override
  int get totalPages => 1;
  @override
  int get pageSize => 40;
  @override
  bool get isLoading => false;
  @override
  bool get isError => false;
  @override
  String getItemId(String item) => item;
  @override
  String? buildItemTitle(String item) => item;

  @override
  bool get supportsCurrentItem => true;
  @override
  Future<int?> resolveCurrentItemIndex() async => currentIndex;

  @override
  bool isItemExpandable(String item) => expandable.contains(item);
  @override
  bool isItemExpanded(String item) => expanded.contains(item);
  @override
  void toggleItemExpanded(String item) {
    toggleCount++;
    if (!expanded.remove(item)) expanded.add(item);
    notifyListeners();
  }

  @override
  Widget? buildItemExpandedContent(BuildContext context, String item) =>
      isItemExpanded(item) ? Text('children-$item') : null;

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
      [
        GenericItemAction<String>(
          label: 'Remove',
          onPressed: (context, item) {},
        ),
      ];
  @override
  List<String>? get currentBreadcrumbs => null;
  @override
  bool get isRightToLeftBreadcrumbs => false;
}

Future<_ExpandableSource> _pump(
  WidgetTester tester, {
  _ExpandableSource? source,
  FocusNode? wrapperFocus,
}) async {
  final ds = source ??
      _ExpandableSource(List.generate(20, (i) => 'item-$i'));
  final page = PaginatedBrowserPage<String>(dataSource: ds);
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Focus(
      focusNode: wrapperFocus,
      child: Scaffold(body: page),
    ),
  ));
  await tester.pumpAndSettle();
  return ds;
}

void main() {
  testWidgets('only expandable rows show a disclosure chevron', (tester) async {
    await _pump(tester);
    expect(find.byIcon(Icons.expand_more), findsOneWidget);
    expect(find.text('children-item-9'), findsNothing);
  });

  testWidgets('chevron sits immediately left of the more button',
      (tester) async {
    await _pump(tester);
    final trailingRow = find
        .ancestor(
          of: find.byIcon(Icons.expand_more),
          matching: find.byType(Row),
        )
        .first;
    final moreInRow =
        find.descendant(of: trailingRow, matching: find.byIcon(Icons.more_vert));
    expect(moreInRow, findsOneWidget);
    expect(
      tester.getCenter(find.byIcon(Icons.expand_more)).dx,
      lessThan(tester.getCenter(moreInRow).dx),
    );
  });

  testWidgets('tapping the chevron reveals then hides the nested content',
      (tester) async {
    final source = await _pump(tester);

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();
    expect(find.text('children-item-9'), findsOneWidget);
    expect(source.toggleCount, 1);

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();
    expect(find.text('children-item-9'), findsNothing);
    expect(source.toggleCount, 2);
  });

  testWidgets('revealing grows the row in-flow, inside the list',
      (tester) async {
    await _pump(tester);
    final rowTopBefore = tester.getTopLeft(find.text('item-9')).dy;

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();

    // Children render below the row's bottom edge...
    expect(
      tester.getTopLeft(find.text('children-item-9')).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(find.text('item-9')).dy - 1),
    );
    // ...hosted by the list itself (in-flow), NOT by a root overlay. This is
    // what lets the list scroll the expanded children and the following items.
    expect(
      find.descendant(
        of: find.byType(ScrollablePositionedList),
        matching: find.text('children-item-9'),
      ),
      findsOneWidget,
    );
    // The tapped row stays put (no ScrollablePositionedList #443 shift).
    expect(
      tester.getTopLeft(find.text('item-9')).dy,
      closeTo(rowTopBefore, 0.5),
    );
  });

  testWidgets('an expanded row can still be scrolled past', (tester) async {
    await _pump(tester);
    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();

    final childTopBefore = tester.getTopLeft(find.text('children-item-9')).dy;
    await tester.drag(find.text('item-9'), const Offset(0, -160));
    await tester.pumpAndSettle();

    // The in-flow children scroll with the list instead of staying pinned over
    // the following items.
    expect(
      tester.getTopLeft(find.text('children-item-9')).dy,
      lessThan(childTopBefore),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('row tap still plays instead of toggling expansion',
      (tester) async {
    final source = await _pump(tester);
    await tester.tap(find.text('item-9'));
    await tester.pumpAndSettle();
    expect(source.toggleCount, 0);
    expect(find.text('children-item-9'), findsNothing);
  });

  testWidgets('selection mode hides the chevron', (tester) async {
    await _pump(tester);
    await tester.longPress(find.text('item-9'));
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsWidgets);
    expect(find.byIcon(Icons.expand_more), findsNothing);
  });

  testWidgets('revealing does not steal focus from the list',
      (tester) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await _pump(tester, wrapperFocus: focusNode);
    focusNode.requestFocus();
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();
    expect(focusNode.hasFocus, isTrue);
  });
}
