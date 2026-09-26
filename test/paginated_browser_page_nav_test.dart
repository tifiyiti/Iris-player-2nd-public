import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/paginated_browser/data_source/paginated_browser_data_source.dart';
import 'package:iris/features/paginated_browser/models/generic_browser_models.dart';
import 'package:iris/features/paginated_browser/paginated_browser_page.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/utils/platform.dart';
import 'package:iris/widgets/adaptive/keyboard_form_shell.dart';

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

/// The jump dialog's zero-input shortcut with [label] (`null` onPressed == greyed
/// out and inert).
TextButton _shortcut(WidgetTester tester, String label) {
  return tester.widget<TextButton>(
    find.ancestor(
      of: find.text(label),
      matching: find.byType(TextButton),
    ),
  );
}

Future<void> _pumpBrowser(WidgetTester tester, _FakePagedSource source) async {
  await tester.pumpWidget(_wrap(PaginatedBrowserPage<String>(
    dataSource: source,
    showHomePage: false,
    showBackButton: false,
  )));
  await tester.pumpAndSettle();
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

  testWidgets('the jump dialog jumps to the last page without typing',
      (tester) async {
    final source = _FakePagedSource(totalItems: 30, pageSize: 5);
    await source.fetchPage(0, source.pageSize);
    await _pumpBrowser(tester, source);

    await tester.tap(find.text('1/6'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('First page'), findsOneWidget);
    expect(find.text('Last page'), findsOneWidget);
    // Page 1 of 6: the first-page shortcut is a no-op and reads as disabled.
    expect(_shortcut(tester, 'First page').onPressed, isNull);
    expect(_shortcut(tester, 'Last page').onPressed, isNotNull);

    await tester.tap(find.text('Last page'));
    await tester.pumpAndSettle();

    // Dialog closed and the browser landed on the last page.
    expect(find.byType(TextField), findsNothing);
    expect(find.text('6/6'), findsOneWidget);
    expect(find.text('item25'), findsOneWidget);

    // Boundary enablement mirrors itself from the new page.
    await tester.tap(find.text('6/6'));
    await tester.pumpAndSettle();
    expect(_shortcut(tester, 'First page').onPressed, isNotNull);
    expect(_shortcut(tester, 'Last page').onPressed, isNull);

    await tester.tap(find.text('First page'));
    await tester.pumpAndSettle();
    expect(find.text('1/6'), findsOneWidget);
    expect(find.text('item0'), findsOneWidget);
  });

  testWidgets('the jump dialog still accepts a typed page number',
      (tester) async {
    final source = _FakePagedSource(totalItems: 30, pageSize: 5);
    await source.fetchPage(0, source.pageSize);
    await _pumpBrowser(tester, source);

    await tester.tap(find.text('1/6'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '3');
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();

    expect(find.text('3/6'), findsOneWidget);
    expect(find.text('item10'), findsOneWidget);
  });

  testWidgets('a landscape phone gets the narrower, parkable jump dialog',
      (tester) async {
    final source = _FakePagedSource(totalItems: 30, pageSize: 5);
    await source.fetchPage(0, source.pageSize);

    debugIsMobilePlatformOverride = true;
    addTearDown(() => debugIsMobilePlatformOverride = null);
    tester.view.physicalSize = const Size(914, 411);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await _pumpBrowser(tester, source);
    await tester.tap(find.text('1/6'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('keyboard_form_drag_handle')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('keyboard_form_resize_grip')), findsOneWidget);
    expect(tester.getSize(find.byType(TextField)).width,
        lessThan(kKeyboardFormMaxWidth),
        reason: 'a sideways phone must not get the 560px slab');
  });

  testWidgets('a desktop window keeps the plain centered jump dialog',
      (tester) async {
    final source = _FakePagedSource(totalItems: 30, pageSize: 5);
    await source.fetchPage(0, source.pageSize);

    debugIsMobilePlatformOverride = false;
    addTearDown(() => debugIsMobilePlatformOverride = null);

    await _pumpBrowser(tester, source);
    await tester.tap(find.text('1/6'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byKey(const ValueKey('keyboard_form_drag_handle')), findsNothing);
    expect(find.byKey(const ValueKey('keyboard_form_resize_grip')), findsNothing);
  });

  testWidgets('an empty list never opens the jump dialog', (tester) async {
    // `totalPages` floors at 1 even for zero items, so the counter still reads
    // "1/1" and stayed tappable. The dialog that opened could then only ever
    // fail validation (1..1 is fine, but there is no page 1 to show) — with the
    // two boundary shortcuts greyed out, i.e. a dialog with no way out but
    // Cancel. A list with no pages has nothing to jump between, so the prompt
    // must not appear at all.
    final source = _FakePagedSource(totalItems: 0, pageSize: 5);
    await source.fetchPage(0, source.pageSize);
    await _pumpBrowser(tester, source);

    await tester.tap(find.text('1/1'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing,
        reason: 'no pages means no jump target — do not open a dead dialog');
  });

  testWidgets('the per-page prompt quotes the real ceiling, not the old '
      '100,000', (tester) async {
    // The copy used to hardcode "1 and 100,000" while the validator rejected
    // anything past 1000, so the prompt advertised a range it refused. The
    // ceiling is now a placeholder fed from the one constant that also guards
    // the stores.
    final source = _FakePagedSource(totalItems: 30, pageSize: 5);
    await source.fetchPage(0, source.pageSize);
    await _pumpBrowser(tester, source);

    await tester.tap(find.text('30/5'));
    await tester.pumpAndSettle();

    expect(find.textContaining('1 and $kMaxBrowserPageSize'), findsOneWidget);
    expect(find.textContaining('100,000'), findsNothing);

    // The rejection message quotes the same ceiling.
    await tester.enterText(find.byType(TextField), '100000');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a number between 1 and $kMaxBrowserPageSize'),
        findsOneWidget);
  });

  testWidgets('the per-page prompt rejects a size past the ceiling',
      (tester) async {
    // A page is materialized in memory, so the size is a budget, not a
    // preference: the old 100000 ceiling asked one resolve to build a hundred
    // thousand rows on the UI isolate.
    final source = _FakePagedSource(totalItems: 30, pageSize: 5);
    await source.fetchPage(0, source.pageSize);
    await _pumpBrowser(tester, source);

    await tester.tap(find.text('30/5'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '100000');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget,
        reason: 'out-of-range must keep the prompt open with its error');
    expect(tester.takeException(), isNull);

    // The ceiling itself is accepted.
    await tester.enterText(find.byType(TextField), '$kMaxBrowserPageSize');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
  });

  group('clampPageSize', () {
    test('keeps a legal size untouched', () {
      expect(clampPageSize(100), 100);
      expect(clampPageSize(kMaxBrowserPageSize), kMaxBrowserPageSize);
    });

    test('pins both ends of the range', () {
      expect(clampPageSize(0), 1);
      expect(clampPageSize(-5), 1);
      expect(clampPageSize(100000), kMaxBrowserPageSize);
    });
  });
}
