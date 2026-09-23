import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/paginated_browser/data_source/paginated_browser_data_source.dart';
import 'package:iris/features/paginated_browser/models/generic_browser_models.dart';
import 'package:iris/features/paginated_browser/paginated_browser_controller.dart';
import 'package:iris/features/paginated_browser/widgets/unified_item_tile.dart';

/// Windows AXTree-corruption mitigation (flutter/flutter#182444 family).
///
/// Paged popups mount dozens of [UnifiedItemTile]s and scrolling
/// unmounts/remounts them continuously. Two contracts:
///  1. no hover Tooltip on the row popup (its OverlayPortal grafts into the
///     ROOT overlay from inside a two-pane semantics viewport — the
///     ListView+Tooltip race that corrupts the engine's AXTree);
///  2. a pure rebuild (controller notify without data change) must not
///     mutate semantics at all.
class _FakeDS extends PaginatedBrowserDataSource<String> {
  final int _totalItems;
  final int _currentPage = 0;
  List<String> _items = [];

  _FakeDS({required int totalItems}) : _totalItems = totalItems {
    _items = [for (var i = 0; i < _totalItems; i++) 'item$i'];
  }

  @override
  int get totalItems => _totalItems;

  @override
  int get currentPage => _currentPage;

  @override
  int get totalPages => 1;

  @override
  int get pageSize => _totalItems;

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
  Widget? buildItemTitleWidget(BuildContext context, String item) => null;

  @override
  Widget buildTileContent(BuildContext context, String item) =>
      const SizedBox.shrink();

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
      [
        GenericItemAction<String>(
          label: 'More',
          onPressed: (_, __) {},
        ),
      ];

  @override
  bool get supportsCurrentItem => false;

  @override
  Future<int?> resolveCurrentItemIndex() async => null;
}

class _Snapshot {
  _Snapshot(this.total, this.labels);
  final int total;
  final List<String> labels;

  @override
  String toString() => 'total=$total labels=$labels';
}

_Snapshot _snapshot() {
  var total = 0;
  final labels = <String>[];
  void visit(SemanticsNode node) {
    total++;
    if (node.label.trim().isNotEmpty) labels.add(node.label);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  final root = RendererBinding.instance.renderViews.first.owner
      ?.semanticsOwner
      ?.rootSemanticsNode;
  if (root != null) visit(root);
  return _Snapshot(total, labels);
}

Widget _harness(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(width: 400, height: 80, child: child),
      ),
    ),
  );
}

void main() {
  testWidgets('unified item tile is an atomic semantics boundary',
      (tester) async {
    final handle = tester.ensureSemantics();
    final controller = PaginatedBrowserController<String>();
    final ds = _FakeDS(totalItems: 3);

    Widget tile(String item) => UnifiedItemTile<String>(
          item: item,
          pageItems: ds.items,
          controller: controller,
          dataSource: ds,
        );

    // Control: the SAME visual content as a bare ListTile (title + trailing
    // popup). The tile must not introduce any Tooltip widget: the trailing
    // popup's default "Show menu" hover Tooltip mounts an OverlayPortal into
    // the ROOT overlay while the mouse passes over scrolling rows — the
    // ListView+Tooltip graft race (#182444) — so it must be gone.
    final bareContent = ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
      visualDensity: const VisualDensity(horizontal: 0, vertical: -4),
      title: const Text('item0'),
      trailing: GestureDetector(
        behavior: HitTestBehavior.opaque,
        child: PopupMenuButton<int>(
          icon: const Icon(Icons.more_vert),
          tooltip: '',
          itemBuilder: (context) => <PopupMenuEntry<int>>[],
        ),
      ),
      onTap: () {},
      onLongPress: () {},
    );

    await tester.pumpWidget(_harness(bareContent));
    await tester.pumpAndSettle();
    final bare = _snapshot();

    await tester.pumpWidget(_harness(tile('item0')));
    await tester.pumpAndSettle();
    final mounted = _snapshot();

    // Same semantics shape as the bare control: no extra tooltip nodes.
    expect(mounted.total, bare.total,
        reason: 'tile must match bare content node count (bare=$bare '
            'tile=$mounted)');
    expect(
      find.descendant(
        of: find.byType(UnifiedItemTile<String>),
        matching: find.byWidgetPredicate(
            (w) => w is Tooltip && (w.message?.isNotEmpty ?? false)),
      ),
      findsNothing,
      reason: 'row popup must not carry an active (non-empty) hover Tooltip',
    );

    // The tile announces its title exactly once.
    expect(mounted.labels.where((l) => l == 'item0').length, 1,
        reason: 'title must appear exactly once ($mounted)');
    expect(mounted.total, greaterThan(0));

    // A controller notify WITHOUT any data change (pure rebuild — happens
    // on every page-level store event) must not mutate semantics.
    controller.notifyListeners();
    await tester.pumpAndSettle();
    final afterNotify = _snapshot();
    expect(afterNotify.total, mounted.total,
        reason: 'pure rebuild must not add/remove semantics nodes '
            '(before=$mounted after=$afterNotify)');
    expect(afterNotify.labels, mounted.labels);

    handle.dispose();
  });
}
