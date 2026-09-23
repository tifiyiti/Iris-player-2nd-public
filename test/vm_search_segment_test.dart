import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/search/data_source/media_search_data_source.dart';
import 'package:iris/features/media_library/search/model/search_result_item.dart';
import 'package:iris/features/paginated_browser/data_source/paginated_browser_data_source.dart';
import 'package:iris/features/paginated_browser/models/generic_browser_models.dart';
import 'package:iris/features/paginated_browser/paginated_browser_controller.dart';
import 'package:iris/features/paginated_browser/paginated_browser_page.dart';
import 'package:iris/features/virtual_media/rule/vm_title_composer.dart';
import 'package:iris/l10n/app_localizations.dart';

/// Fake source whose `isItemSelectable` blocks the configured ids.
class _SelectableDS extends PaginatedBrowserDataSource<String> {
  _SelectableDS(this.blocked) {
    fetchPage(0, 10);
  }

  final Set<String> blocked;
  int _currentPage = 0;
  List<String> _items = const [];

  @override
  int get totalItems => _items.length;

  @override
  int get currentPage => _currentPage;

  @override
  int get totalPages => 1;

  @override
  int get pageSize => 10;

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
  bool isItemSelectable(String item) => !blocked.contains(item);

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

/// A source whose pages are BASE-slot windows: page 1 holds only two rows
/// (slots 5 and 7) because slot 6 was absorbed by a merged group row.
class _SparsePageDS extends _SelectableDS {
  _SparsePageDS() : super(const {});

  int _page = 0;

  static const _rowsByPage = <int, List<int>>{
    0: [0, 1, 2, 3, 4],
    1: [5, 7],
    2: [10, 11],
  };

  @override
  int get pageSize => 5;

  @override
  int get totalItems => 12;

  @override
  int get totalPages => 3;

  @override
  int get currentPage => _page;

  @override
  Future<void> fetchPage(int targetPage, int currentSize) async {
    _page = targetPage;
  }

  @override
  Future<int?> resolveCurrentItemIndex() async => 7;

  @override
  bool get supportsCurrentItem => true;

  @override
  int rowInCurrentPage(int index) =>
      (_rowsByPage[_page] ?? const []).indexOf(index);
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

void main() {
  group('virtual search segment model', () {
    test('prefix is the fixed language-neutral marker', () {
      expect(kVmDisplayPrefix, '[vm] ');
    });

    test('virtual group id is scope-keyed, never colliding with its file', () {
      final vm = SearchResultItem(
        storageId: 's',
        path: 'a/1.mp4',
        name: '${kVmDisplayPrefix}A · 1',
        origin: SearchResultOrigin.virtualGroup,
        vmScopeKey: 'r|a|#1',
        segmentCount: 3,
        occurrenceIndex: 2,
      );
      final file = SearchResultItem(
        storageId: 's',
        path: 'a/1.mp4',
        name: '1.mp4',
        origin: SearchResultOrigin.dbSource,
      );
      expect(vm.isVirtualGroup, isTrue);
      expect(file.isVirtualGroup, isFalse);
      expect(vm.id, 'vm:r|a|#1');
      expect(file.id, 's:a/1.mp4');
      expect(vm.id, isNot(file.id));
    });
  });

  group('SearchVirtualPageMerger with a virtual tail (v5-D2)', () {
    SearchResultItem db(int i) => SearchResultItem(
          storageId: 's',
          path: 'db$i.mp4',
          name: 'db$i.mp4',
          origin: SearchResultOrigin.dbSource,
        );
    SearchResultItem ex(int i) => SearchResultItem(
          storageId: 's',
          path: 'ex$i.mp4',
          name: 'ex$i.mp4',
          origin: SearchResultOrigin.explicitItem,
        );
    SearchResultItem vm(int i) => SearchResultItem(
          storageId: 's',
          path: 'vm$i.mp4',
          name: '${kVmDisplayPrefix}vm$i.mp4',
          origin: SearchResultOrigin.virtualGroup,
          vmScopeKey: 'r|a|#$i',
        );

    test('tail order is explicit-then-virtual, total is consistent', () async {
      final dbItems = [db(0), db(1)];
      final tail = [ex(0), vm(0), vm(1)];
      final m = SearchVirtualPageMerger(dbTotal: 2, explicit: tail);
      expect(m.total, 5);
      final page = await m.buildPage(0, 100, (i) async => dbItems[i]);
      expect(
        page.map((e) => e.origin).toList(),
        const [
          SearchResultOrigin.dbSource,
          SearchResultOrigin.dbSource,
          SearchResultOrigin.explicitItem,
          SearchResultOrigin.virtualGroup,
          SearchResultOrigin.virtualGroup,
        ],
      );
    });

    test('cross-page walk loses nothing and duplicates nothing', () async {
      final dbItems = [db(0), db(1), db(2)];
      final tail = [ex(0), vm(0), vm(1)];
      final m = SearchVirtualPageMerger(dbTotal: 3, explicit: tail);

      final pages = <List<SearchResultItem>>[];
      for (var p = 0; p < 3; p++) {
        pages.add(await m.buildPage(p, 2, (i) async => dbItems[i]));
      }
      final ids = pages.expand((p) => p).map((e) => e.id).toList();
      expect(ids, [
        's:db0.mp4',
        's:db1.mp4',
        's:db2.mp4',
        's:ex0.mp4',
        'vm:r|a|#0',
        'vm:r|a|#1',
      ]);
      expect(ids.toSet().length, ids.length);
      expect(pages.fold<int>(0, (n, p) => n + p.length), m.total);
    });
  });

  group('base-slot page windows map index -> (page, row) for auto-locate', () {
    test('the default page math matches a base-slot window', () {
      final ds = _SparsePageDS();
      expect(ds.pageForIndex(0), 0);
      expect(ds.pageForIndex(4), 0);
      // Slots 5..9 live on page 1, slots 10..14 on page 2.
      expect(ds.pageForIndex(5), 1);
      expect(ds.pageForIndex(7), 1);
      expect(ds.pageForIndex(11), 2);
    });

    test('a page shorter than pageSize resolves the row by slot, not by dense '
        'offset', () async {
      final ds = _SparsePageDS();
      await ds.fetchPage(1, ds.pageSize);
      expect(ds.rowInCurrentPage(5), 0);
      // The dense offset would say 7 - 1*5 = 2; the row is the 2nd of the page.
      expect(ds.rowInCurrentPage(7), 1);
      // An absorbed slot has no row, so nothing is centered.
      expect(ds.rowInCurrentPage(6), -1);
      expect(ds.rowInCurrentPage(9), -1);
    });

    testWidgets('auto-locate opens the page that owns the slot',
        (tester) async {
      final ds = _SparsePageDS();
      final controller = PaginatedBrowserController<String>();
      await tester.pumpWidget(_wrap(PaginatedBrowserPage<String>(
        dataSource: ds,
        controller: controller,
        showHomePage: false,
        showBackButton: false,
      )));
      await tester.pumpAndSettle();

      // The current slot is 7, which lives on page 1 (window 5..9).
      expect(ds.currentPage, 1);
      expect(ds.rowInCurrentPage(7), 1);
    });
  });

  group('selection excludes non-selectable rows', () {
    test('enterSelectionMode on a blocked item selects nothing', () {
      final ds = _SelectableDS({'b'});
      final c = PaginatedBrowserController<String>();
      c.enterSelectionMode('b', ds);
      expect(c.isSelectionMode, isTrue);
      expect(c.selectedIds, isEmpty);
      expect(c.anchorItem, isNull);
    });

    test('toggleSelection ignores blocked items', () {
      final ds = _SelectableDS({'b'});
      final c = PaginatedBrowserController<String>();
      c.toggleSelection('b', ds);
      expect(c.selectedIds, isEmpty);
      c.toggleSelection('a', ds);
      expect(c.selectedIds, {'a'});
    });

    test('select-all / invert / range skip blocked items', () {
      final ds = _SelectableDS({'b'});
      final c = PaginatedBrowserController<String>();
      const page = ['a', 'b', 'c', 'd'];

      c.selectAllOnPage(page, ds);
      expect(c.selectedIds, {'a', 'c', 'd'});

      // XOR over selectable rows only: a/c/d are cleared, b stays untouched.
      c.invertSelectionOnPage(page, ds);
      expect(c.selectedIds, isEmpty);

      c.selectedIds
        ..clear()
        ..add('a');
      c.anchorItem = 'a';
      // Range a..d covers b, c and d; b is blocked, so c and d are toggled.
      c.processRangeXorSelection('d', page, ds);
      expect(c.selectedIds, {'a', 'c', 'd'});
    });

    test('range on a blocked target is a no-op', () {
      final ds = _SelectableDS({'b'});
      final c = PaginatedBrowserController<String>();
      c.enterSelectionMode('a', ds);
      final before = {...c.selectedIds};
      c.processRangeXorSelection('b', const ['a', 'b', 'c'], ds);
      expect(c.selectedIds, before);
    });
  });

  testWidgets(
      'blocked rows render no checkbox and cannot be toggled in selection mode',
      (tester) async {
    final ds = _SelectableDS({'b'});
    final controller = PaginatedBrowserController<String>();
    await tester.pumpWidget(_wrap(PaginatedBrowserPage<String>(
      dataSource: ds,
      controller: controller,
      showHomePage: false,
      showBackButton: false,
    )));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('a'));
    await tester.pumpAndSettle();
    expect(controller.isSelectionMode, isTrue);
    // a + c get checkboxes; b (blocked) renders its icon instead.
    expect(find.byType(Checkbox), findsNWidgets(2));

    await tester.tap(find.text('b'));
    await tester.pumpAndSettle();
    expect(controller.selectedIds.contains('b'), isFalse);
    expect(controller.selectedIds, {'a'});
  });
}
