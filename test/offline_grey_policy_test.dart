import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/paginated_browser/data_source/paginated_browser_data_source.dart';
import 'package:iris/features/paginated_browser/models/generic_browser_models.dart';
import 'package:iris/features/paginated_browser/paginated_browser_controller.dart';
import 'package:iris/features/paginated_browser/paginated_browser_page.dart';
import 'package:iris/features/webdav_discovery/view/webdav_connect_error_dialog.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/enums/storage_list_error.dart';

/// Offline-grey policy (RED first):
/// - failure dialog: [Cancel][Edit][Retry] left-to-right, no device-power
///   checklist, offline note instead;
/// - action models carry `enabled` (default true);
/// - renderers honor it: null onPressed / PopupMenuItem(enabled: false).
void main() {
  group('failure dialog button order and copy', () {
    Widget tree(Future<WebdavConnectAction> Function(BuildContext) show) {
      return MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => show(context),
              child: const Text('open'),
            ),
          ),
        ),
      );
    }

    testWidgets('actions read Cancel, Edit, Retry left to right',
        (tester) async {
      await tester.pumpWidget(tree(
        (context) => showWebdavConnectFailure(
          context,
          endpoint: '192.168.1.9',
          errorKind: StorageListErrorKind.unreachable,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      double dxOf(String label) =>
          tester.getCenter(find.widgetWithText(TextButton, label)).dx;
      expect(dxOf('Cancel'), lessThan(dxOf('Edit')));
      expect(dxOf('Edit'), lessThan(dxOf('Retry')));
    });

    testWidgets('states offline-only facts, never device power', (tester) async {
      await tester.pumpWidget(tree(
        (context) => showWebdavConnectFailure(
          context,
          endpoint: '192.168.1.9',
          errorKind: StorageListErrorKind.unreachable,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
            'Library entries stay greyed and browse-only until it reconnects.'),
        findsOneWidget,
      );
      expect(find.textContaining('Wi-Fi'), findsNothing);
      expect(find.textContaining('is on'), findsNothing);
    });
  });

  group('action models carry enabled (default true)', () {
    test('CustomSelectionAction defaults to enabled', () {
      final a = CustomSelectionAction<String>(
        icon: const Icon(Icons.play_arrow),
        label: 'x',
        onPressed: (ctx, selected) async => true,
      );
      expect(a.enabled, isTrue);
    });

    test('GenericItemAction defaults to enabled', () {
      final a = GenericItemAction<String>(
        label: 'x',
        onPressed: (ctx, item) {},
      );
      expect(a.enabled, isTrue);
    });
  });

  group('renderers honor enabled=false', () {
    testWidgets('disabled page action has null onPressed', (tester) async {
      await _pump(tester, _GreyDS());
      final btn = _iconByTooltip(tester, 'ScanX');
      expect(btn.onPressed, isNull);
    });

    testWidgets('disabled sub-action renders PopupMenuItem(enabled: false)',
        (tester) async {
      await _pump(tester, _GreyDS());
      await tester.tap(find.byTooltip('MoreX'));
      await tester.pumpAndSettle();
      final item = tester.widget<PopupMenuItem<PageAction>>(
        find.widgetWithText(PopupMenuItem<PageAction>, 'SubX'),
      );
      expect(item.enabled, isFalse);
    });

    testWidgets('disabled selection action has null onPressed',
        (tester) async {
      await _pump(tester, _GreyDS());
      await tester.longPress(find.text('a'));
      await tester.pumpAndSettle();
      final btn = _iconByTooltip(tester, 'PlayX');
      expect(btn.onPressed, isNull);
    });

    testWidgets('enabledFor=false disables the selection action',
        (tester) async {
      await _pump(tester, _GreyDS());
      await tester.longPress(find.text('a'));
      await tester.pumpAndSettle();
      final btn = _iconByTooltip(tester, 'PlayY');
      expect(btn.onPressed, isNull);
    });

    testWidgets('disabled trailing action renders PopupMenuItem(enabled: false)',
        (tester) async {
      await _pump(tester, _GreyDS());
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      final item = tester.widget<PopupMenuItem<int>>(
        find.widgetWithText(PopupMenuItem<int>, 'TrailX'),
      );
      expect(item.enabled, isFalse);
    });
  });
}

IconButton _iconByTooltip(WidgetTester tester, String tip) =>
    tester
        .widgetList<IconButton>(find.byType(IconButton))
        .firstWhere((b) => b.tooltip == tip);

/// One item, every action disabled: page, sub, selection, trailing.
class _GreyDS extends PaginatedBrowserDataSource<String> {
  @override
  int get totalItems => 1;
  @override
  int get currentPage => 0;
  @override
  int get totalPages => 1;
  @override
  int get pageSize => 50;
  @override
  bool get isLoading => false;
  @override
  bool get isError => false;
  @override
  List<String> get items => const <String>['a'];
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
  List<PageAction> buildCustomPageActions(BuildContext context) => [
        const PageAction(
          icon: Icon(Icons.sync),
          label: 'ScanX',
          onPressed: null,
        ),
        PageAction(
          icon: const Icon(Icons.more_horiz),
          label: 'MoreX',
          subActions: const [
            PageAction(
              icon: Icon(Icons.refresh),
              label: 'SubX',
              onPressed: null,
            ),
          ],
        ),
      ];

  @override
  List<CustomSelectionAction<String>> buildCustomSelectionActions(
          BuildContext context) =>
      [
        CustomSelectionAction<String>(
          icon: const Icon(Icons.play_arrow),
          label: 'PlayX',
          enabled: false,
          onPressed: (ctx, selected) async => true,
        ),
        CustomSelectionAction<String>(
          icon: const Icon(Icons.playlist_add),
          label: 'PlayY',
          enabledFor: (selected) => false,
          onPressed: (ctx, selected) async => true,
        ),
      ];

  @override
  List<GenericItemAction<String>> getItemTrailingActions(
          BuildContext context, String item) =>
      [
        GenericItemAction<String>(
          label: 'TrailX',
          enabled: false,
          onPressed: (ctx, i) {},
        ),
      ];
}

Future<void> _pump(WidgetTester tester, _GreyDS ds) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SizedBox(
        width: 800,
        height: 600,
        child: PaginatedBrowserPage<String>(
          dataSource: ds,
          controller: PaginatedBrowserController<String>(),
          onClose: () {},
          showHomePage: false,
          showBackButton: false,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}
