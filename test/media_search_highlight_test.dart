import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/search/view/widgets/search_highlight_text.dart';
import 'package:iris/features/paginated_browser/data_source/paginated_browser_data_source.dart';
import 'package:iris/features/paginated_browser/models/generic_browser_models.dart';
import 'package:iris/features/paginated_browser/paginated_browser_controller.dart';
import 'package:iris/features/paginated_browser/paginated_browser_page.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/utils/escape_like.dart';

/// Collects the text of every [TextSpan] whose style carries a non-null
/// [TextStyle.backgroundColor] (i.e. the highlight spans).
List<String> _highlightedTexts(TextSpan root) {
  final out = <String>[];
  void walk(InlineSpan span) {
    if (span is TextSpan) {
      if (span.text != null && span.style?.backgroundColor != null) {
        out.add(span.text!);
      }
      for (final child in span.children ?? const <InlineSpan>[]) {
        walk(child);
      }
    }
  }

  walk(root);
  return out;
}

/// Highlighted texts across every RichText in the tree. `Text` renders an
/// internal RichText, so scanning all of them is the reliable way to tell
/// highlighted output apart from plain text.
List<String> allHighlightedTexts(WidgetTester tester) {
  final out = <String>[];
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    if (rich.text is TextSpan) out.addAll(_highlightedTexts(rich.text as TextSpan));
  }
  return out;
}

/// Number of RichText widgets that actually contain a highlighted span.
int highlightedRichTextCount(WidgetTester tester) {
  var count = 0;
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    if (rich.text is TextSpan &&
        _highlightedTexts(rich.text as TextSpan).isNotEmpty) {
      count++;
    }
  }
  return count;
}

/// Returns the highlight style of the first highlighted span, or null when
/// none exists.
TextStyle? _firstHighlightStyle(TextSpan root) {
  TextStyle? style;
  void walk(InlineSpan span) {
    if (style != null) return;
    if (span is TextSpan) {
      if (span.text != null && span.style?.backgroundColor != null) {
        style = span.style;
      }
      for (final child in span.children ?? const <InlineSpan>[]) {
        walk(child);
      }
    }
  }

  walk(root);
  return style;
}

void main() {
  group('highlightRanges (F-006 matching semantics)', () {
    test('single token, case-insensitive substring', () {
      expect(highlightRanges('MyMovie.mp4', ['movie']), [(2, 7)]);
      expect(highlightRanges('MyMovie.mp4', ['MYMOVIE']), [(0, 7)]);
    });

    test('multiple tokens produce one range each', () {
      expect(highlightRanges('accb.mp4', ['a', 'b']), [(0, 1), (3, 4)]);
    });

    test('overlapping token matches merge into a single range', () {
      expect(highlightRanges('abab', ['aba', 'ab']), [(0, 4)]);
    });

    test('adjacent token matches merge into a single range', () {
      expect(highlightRanges('aabb', ['aa', 'bb']), [(0, 4)]);
    });

    test('repeated separated occurrences are all highlighted', () {
      expect(highlightRanges('ba-ba', ['ba']), [(0, 2), (3, 5)]);
    });

    test('CJK substrings (no case folding needed)', () {
      expect(highlightRanges('我的电影合集.mp4', ['我的', '合集']),
          [(0, 2), (4, 6)]);
    });

    test('no match yields no ranges', () {
      expect(highlightRanges('foo.mp4', ['zzz']), isEmpty);
    });

    test('empty tokens yield no ranges', () {
      expect(highlightRanges('foo.mp4', []), isEmpty);
    });

    test('% and _ are treated as literal characters', () {
      expect(highlightRanges('a%b_c.mp4', ['%b']), [(1, 3)]);
      expect(highlightRanges('a%b_c.mp4', ['b_']), [(2, 4)]);
    });
  });

  group('SearchHighlightText', () {
    Widget wrap(Widget child) => MaterialApp(
          home: Scaffold(body: Center(child: child)),
        );

    testWidgets('matched tokens render as background-highlighted RichText',
        (tester) async {
      await tester.pumpWidget(
        wrap(const SearchHighlightText(name: 'MyMovie.mp4', query: 'movie')),
      );

      // The original-case substring is highlighted (MyMovie.mp4 → 'Movie').
      expect(allHighlightedTexts(tester), ['Movie']);
      final full = tester
          .widgetList<RichText>(find.byType(RichText))
          .map((r) => (r.text as TextSpan).toPlainText());
      expect(full, contains('MyMovie.mp4'));
    });

    testWidgets('highlight adds background + color, never bold', (tester) async {
      await tester.pumpWidget(
        wrap(const SearchHighlightText(name: 'accb.mp4', query: 'a b')),
      );

      final style = _firstHighlightStyle(tester
          .widget<RichText>(find.byType(RichText))
          .text as TextSpan);
      expect(style, isNotNull);
      expect(style!.backgroundColor, isNotNull);
      expect(style.color, isNotNull,
          reason: 'matched text should change color for readability');
      expect(style.fontWeight, isNull,
          reason: 'highlight must not bold the matched substring');
    });

    testWidgets('multiple tokens highlight all matched spans', (tester) async {
      await tester.pumpWidget(
        wrap(const SearchHighlightText(name: 'accb.mp4', query: 'a b')),
      );

      expect(allHighlightedTexts(tester), ['a', 'b']);
    });

    testWidgets('empty query produces no highlight', (tester) async {
      await tester.pumpWidget(
        wrap(const SearchHighlightText(name: 'accb.mp4', query: '')),
      );

      expect(highlightedRichTextCount(tester), 0);
      expect(find.text('accb.mp4'), findsOneWidget);
    });

    testWidgets('query with no match produces no highlight', (tester) async {
      await tester.pumpWidget(
        wrap(const SearchHighlightText(name: 'accb.mp4', query: 'zzz')),
      );

      expect(highlightedRichTextCount(tester), 0);
      expect(find.text('accb.mp4'), findsOneWidget);
    });
  });

  group('UnifiedItemTile title extension point', () {
    testWidgets('prefers buildItemTitleWidget over buildItemTitle',
        (tester) async {
      final ds = _HighlightDS(totalItems: 5, pageSize: 5);
      await tester.pumpWidget(_wrap(PaginatedBrowserPage<String>(
        dataSource: ds,
        controller: PaginatedBrowserController<String>(),
        onClose: () {},
        showHomePage: false,
        showBackButton: false,
      )));
      await tester.pumpAndSettle();

      // One highlighted RichText per visible tile → the widget path was used
      // instead of the plain Text(title) fallback.
      expect(highlightedRichTextCount(tester), 5);
      expect(find.text('item0', findRichText: true), findsOneWidget);
    });
  });
}

/// Fake data source that renders titles through `buildItemTitleWidget`, used
/// to prove the generic tile prefers the widget path over `buildItemTitle`.
class _HighlightDS extends PaginatedBrowserDataSource<String> {
  final int _totalItems;
  final int _pageSize;

  int _currentPage = 0;
  bool _loading = false;
  List<String> _items = [];

  _HighlightDS({required int totalItems, required int pageSize})
      : _totalItems = totalItems,
        _pageSize = pageSize {
    fetchPage(0, _pageSize);
  }

  @override
  int get totalItems => _totalItems;

  @override
  int get currentPage => _currentPage;

  @override
  int get totalPages => (totalItems / _pageSize).ceil().clamp(1, 99999);

  @override
  int get pageSize => _pageSize;

  @override
  bool get isLoading => _loading;

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
    _loading = true;
    notifyListeners();
    await Future<void>.delayed(Duration.zero);
    _currentPage = targetPage;
    final start = targetPage * _pageSize;
    final end = (start + _pageSize).clamp(0, _totalItems);
    _items = [for (var i = start; i < end; i++) 'item$i'];
    _loading = false;
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
  Widget? buildItemTitleWidget(BuildContext context, String item) =>
      SearchHighlightText(name: item, query: 'm');

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
