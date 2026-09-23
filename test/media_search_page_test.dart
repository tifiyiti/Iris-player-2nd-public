import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/media_library/search/model/search_context.dart';
import 'package:iris/features/media_library/search/model/search_result_item.dart';
import 'package:iris/features/media_library/search/model/search_scope.dart';
import 'package:iris/features/media_library/search/store/search_browser_store.dart';
import 'package:iris/features/media_library/search/view/media_search_page.dart';
import 'package:iris/features/media_library/search/view/widgets/media_search_bar.dart';
import 'package:iris/features/paginated_browser/paginated_browser_page.dart';
import 'package:iris/features/paginated_browser/widgets/dynamic_responsive_bar.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/widgets/popup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The search data source touches useMediaLibContentStore(), whose factory
  // reads DbModule — initialize it once with an in-memory database.
  setUpAll(() {
    final db = AppDatabase(NativeDatabase.memory());
    DbModule.init(db);
  });

  double searchBarSlotInset(WidgetTester tester) {
    // The keyboard inset is applied to the search-bar slot only: the nearest
    // Padding ancestor of MediaSearchBar (the slot wrapper in _BottomBarSection).
    final padding = tester.widgetList<Padding>(
      find.ancestor(
        of: find.byType(MediaSearchBar),
        matching: find.byType(Padding),
      ),
    ).first;
    return padding.padding.resolve(TextDirection.ltr).bottom;
  }

  bool pageKeyboardAware(WidgetTester tester) {
    final page = tester.widget<PaginatedBrowserPage<SearchResultItem>>(
      find.byWidgetPredicate(
        (w) => w is PaginatedBrowserPage<SearchResultItem>,
      ),
    );
    return page.keyboardAware;
  }

  /// Pumps the search page inside a [StoreScope] + [MaterialApp]. The keyboard
  /// inset is driven by [insetNotifier] so tests can change it IN PLACE within
  /// the same element tree (only the MediaQuery subtree rebuilds).
  Future<void> pumpSearchPage(
    WidgetTester tester, {
    required ValueNotifier<double> insetNotifier,
  }) async {
    useSearchBrowserStore().setMediaLibEntry(
      const SearchContext(
        entryContext: SearchEntryContext.libPathTreeDir,
        storageId: 's',
        parentPath: 'a',
      ),
    );
    final base = MediaQueryData.fromView(tester.view);
    await tester.pumpWidget(
      StoreScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ValueListenableBuilder<double>(
            valueListenable: insetNotifier,
            builder: (context, inset, _) => MediaQuery(
              data: base.copyWith(
                viewInsets: EdgeInsets.only(bottom: inset),
              ),
              // In the real app the Popup wraps its content in a Card→Material;
              // the search TextField requires a Material ancestor.
              child: const Material(
                color: Colors.transparent,
                child: MediaSearchPage(direction: PopupDirection.right),
              ),
            ),
          ),
        ),
      ),
    );
    // Deferred l10n delegates load async — settle so the page mounts.
    await tester.pumpAndSettle();
  }

  testWidgets(
      'keyboard open: search bar slot lifts and the bottom toolbar is removed '
      '(v7-D1, 方案 Y)', (tester) async {
    final inset = ValueNotifier<double>(400);
    await pumpSearchPage(tester, insetNotifier: inset);

    expect(pageKeyboardAware(tester), isTrue);
    expect(searchBarSlotInset(tester), 400);
    // Toolbar dropped from the layout while typing → its space is released.
    expect(
      find.byWidgetPredicate((w) => w is DynamicResponsiveBar),
      findsNothing,
    );
  });

  testWidgets('no keyboard inset keeps the toolbar visible (desktop / closed IME)',
      (tester) async {
    final inset = ValueNotifier<double>(0);
    await pumpSearchPage(tester, insetNotifier: inset);

    expect(pageKeyboardAware(tester), isTrue);
    expect(
      find.byWidgetPredicate((w) => w is DynamicResponsiveBar),
      findsOneWidget,
    );
  });

  testWidgets('entering the search page auto-focuses the input (v8-D2)',
      (tester) async {
    final inset = ValueNotifier<double>(0);
    await pumpSearchPage(tester, insetNotifier: inset);
    await tester.pump(); // let the post-frame requestFocus run

    final textField = tester.widget<TextField>(
      find.descendant(
        of: find.byType(MediaSearchBar),
        matching: find.byType(TextField),
      ),
    );
    final primary = FocusManager.instance.primaryFocus;
    expect(primary, isNotNull);
    expect(primary, textField.focusNode,
        reason: 'the search input should receive focus on entry');
  });

  testWidgets(
      'keyboard open/close does NOT recreate the search bar element '
      '(v7-D1 crash regression)', (tester) async {
    final inset = ValueNotifier<double>(0);
    await pumpSearchPage(tester, insetNotifier: inset);

    // Focus the search field, then open the keyboard (viewInsets changes in
    // place). The focused TextField must NOT be torn down mid-IME-appearance.
    await tester.tap(find.byType(MediaSearchBar));
    await tester.pump();
    final before = tester.element(find.byType(MediaSearchBar));

    inset.value = 400;
    await tester.pump();
    final opened = tester.element(find.byType(MediaSearchBar));
    expect(identical(before, opened), isTrue, reason: 'search bar element was recreated');
    expect(searchBarSlotInset(tester), 400);
    expect(
      find.byWidgetPredicate((w) => w is DynamicResponsiveBar),
      findsNothing,
    );

    // Closing the keyboard restores the toolbar without recreating the bar.
    inset.value = 0;
    await tester.pump();
    final closed = tester.element(find.byType(MediaSearchBar));
    expect(identical(before, closed), isTrue, reason: 'search bar element was recreated');
    expect(
      find.byWidgetPredicate((w) => w is DynamicResponsiveBar),
      findsOneWidget,
    );
  });
}
