import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/paginated_browser/models/browser_toolbar_layout.dart';
import 'package:iris/features/paginated_browser/models/generic_browser_models.dart';
import 'package:iris/features/paginated_browser/paginated_browser_controller.dart';
import 'package:iris/features/paginated_browser/paginated_browser_page.dart';
import 'package:iris/l10n/app_localizations.dart';

import 'helpers/fake_paged_browser_data_source.dart';

/// V2 of the scenario play queue: a STRICTLY single-row toolbar that keeps only
/// sort / page nav / per-page count / go-to-current, and folds every other
/// action into one overflow button.
///
/// The V1 layout (and every other browser that shares [DynamicResponsiveBar])
/// must stay untouched — the new layout is opt-in via
/// [BrowserToolbarLayout.compactSingleLine].
void main() {
  Widget wrap(Widget child, {double width = 800}) {
    return StoreScope(
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(width: width, height: 600, child: child),
        ),
      ),
    );
  }

  Future<void> pumpBar(
    WidgetTester tester,
    FakePagedBrowserDataSource ds, {
    List<PageAction> overflowActions = const [],
    double width = 800,
  }) async {
    await tester.pumpWidget(wrap(
      PaginatedBrowserPage<String>(
        dataSource: ds,
        controller: PaginatedBrowserController<String>(),
        onClose: () {},
        showHomePage: false,
        showBackButton: false,
        toolbarLayout: BrowserToolbarLayout.compactSingleLine,
        overflowActions: overflowActions,
      ),
      width: width,
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('V2 keeps exactly the six agreed controls in the row',
      (tester) async {
    final ds = FakePagedBrowserDataSource(supportsCurrent: true);
    await pumpBar(tester, ds);

    // Kept in the row.
    expect(find.byIcon(Icons.sort_rounded), findsOneWidget,
        reason: 'sort stays a first-class control');
    expect(find.byIcon(Icons.navigate_before), findsOneWidget);
    expect(find.byIcon(Icons.navigate_next), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget, reason: 'page counter');
    expect(find.text('10/5'), findsOneWidget, reason: 'total / per-page chip');
    expect(find.byIcon(Icons.my_location), findsOneWidget,
        reason: 'locate current playing');
    expect(find.byIcon(Icons.more_vert), findsOneWidget, reason: 'overflow');
    expect(find.byIcon(Icons.close), findsOneWidget);

    // Folded away from the row.
    expect(find.byIcon(Icons.search), findsNothing);
    expect(find.byIcon(Icons.tune), findsNothing);
    expect(find.byIcon(Icons.autorenew_rounded), findsNothing);
    expect(find.byIcon(Icons.casino_outlined), findsNothing);
  });

  testWidgets('V2 renders one row and never wraps', (tester) async {
    final ds = FakePagedBrowserDataSource(
      supportsCurrent: true,
      customActions: [
        for (var i = 0; i < 6; i++)
          PageAction(icon: Icon(Icons.star), label: 'c$i', onPressed: () {}),
      ],
    );
    // 260px is narrower than the controls need: V2 must shrink, not wrap.
    await pumpBar(tester, ds, width: 260);

    expect(find.byType(Wrap), findsNothing,
        reason: 'V2 is a single row by contract — no wrap fallback');
    expect(tester.takeException(), isNull,
        reason: 'a too-narrow container must not overflow');
  });

  testWidgets('V2 folds custom + trailing actions into the overflow menu',
      (tester) async {
    final ds = FakePagedBrowserDataSource(
      supportsCurrent: true,
      customActions: [
        PageAction(
          icon: const Icon(Icons.search),
          label: 'search-action',
          onPressed: () {},
        ),
      ],
      trailingActions: [
        PageAction(
          icon: const Icon(Icons.view_sidebar_rounded),
          label: 'trailing-action',
          onPressed: () {},
        ),
      ],
    );
    await pumpBar(tester, ds);

    expect(find.text('search-action'), findsNothing,
        reason: 'folded actions must not render inline');

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('search-action'), findsOneWidget);
    expect(find.text('trailing-action'), findsOneWidget);
  });

  testWidgets('V2 overflow entries fire their action', (tester) async {
    var searchTapped = false;
    final ds = FakePagedBrowserDataSource(
      supportsCurrent: true,
      customActions: [
        PageAction(
          icon: const Icon(Icons.search),
          label: 'search-action',
          onPressed: () => searchTapped = true,
        ),
      ],
    );
    await pumpBar(tester, ds);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('search-action'));
    await tester.pumpAndSettle();

    expect(searchTapped, isTrue);
  });

  testWidgets('V2 renders a checked overflow row as a checkbox',
      (tester) async {
    var toggled = 0;
    final ds = FakePagedBrowserDataSource(supportsCurrent: true);
    await pumpBar(
      tester,
      ds,
      overflowActions: [
        PageAction(
          icon: const Icon(Icons.account_tree),
          label: 'show-breadcrumb',
          checked: true,
          onPressed: () => toggled++,
        ),
        PageAction(
          icon: const Icon(Icons.swap_horiz),
          label: 'plain-row',
          onPressed: () {},
        ),
      ],
    );
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    final checkbox = find.byType(Checkbox);
    expect(checkbox, findsOneWidget,
        reason: 'only the checked row renders a checkbox');
    expect(
      tester.widget<Checkbox>(checkbox).value,
      isTrue,
    );
    // The plain row must not masquerade as a toggle.
    expect(find.byType(Checkbox), findsOneWidget);

    await tester.tap(find.text('show-breadcrumb'));
    await tester.pumpAndSettle();
    expect(toggled, 1);
  });

  testWidgets('V2 selection mode is a single row with a folded overflow',
      (tester) async {
    var excludeTapped = false;
    final ds = FakePagedBrowserDataSource(
      selectionActions: [
        CustomSelectionAction<String>(
          icon: const Icon(Icons.remove_circle_outline),
          label: 'exclude-selected',
          onPressed: (context, selected) async {
            excludeTapped = true;
            return false; // keep selection mode open
          },
        ),
      ],
    );
    final controller = PaginatedBrowserController<String>();
    await tester.pumpWidget(wrap(
      PaginatedBrowserPage<String>(
        dataSource: ds,
        controller: controller,
        onClose: () {},
        showHomePage: false,
        showBackButton: false,
        toolbarLayout: BrowserToolbarLayout.compactSingleLine,
      ),
    ));
    await tester.pumpAndSettle();

    controller.enterSelectionMode(ds.items.first, ds);
    await tester.pumpAndSettle();

    expect(find.text('exclude-selected'), findsNothing,
        reason: 'selection custom actions fold into the overflow');
    expect(find.byIcon(Icons.select_all), findsNothing);
    expect(find.byIcon(Icons.flip), findsNothing);
    expect(find.byType(Wrap), findsNothing);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('exclude-selected'), findsOneWidget);

    await tester.tap(find.text('exclude-selected'));
    await tester.pumpAndSettle();
    expect(excludeTapped, isTrue);
  });

  testWidgets('V1 (default) keeps the responsive bar untouched',
      (tester) async {
    final ds = FakePagedBrowserDataSource(supportsCurrent: true);
    await tester.pumpWidget(wrap(
      PaginatedBrowserPage<String>(
        dataSource: ds,
        controller: PaginatedBrowserController<String>(),
        onClose: () {},
        showHomePage: false,
        showBackButton: false,
      ),
    ));
    await tester.pumpAndSettle();

    // V1 renders the custom cluster inline and has NO overflow button.
    expect(find.byIcon(Icons.more_vert), findsNothing);
  });

  _goCurrentIconSizeTests();
}

/// The go-to-current crosshair is the same control in all three layouts, so it
/// must be the SAME size in all three — it was 24px everywhere until the V3
/// grid's dense tile made it look oversized, and repeating the number per bar
/// would let the three drift apart again.
void _goCurrentIconSizeTests() {
  for (final entry in <String, BrowserToolbarLayout>{
    'V1': BrowserToolbarLayout.responsive,
    'V2': BrowserToolbarLayout.compactSingleLine,
    'V3': BrowserToolbarLayout.floatingGrid,
  }.entries) {
    testWidgets('${entry.key} renders the crosshair at the shared size',
        (tester) async {
      final ds = FakePagedBrowserDataSource(supportsCurrent: true);
      await tester.pumpWidget(StoreScope(
        child: MaterialApp(
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
                toolbarLayout: entry.value,
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.my_location), findsOneWidget);
      final icon = tester.widget<Icon>(find.byIcon(Icons.my_location));
      // Asserted against the literal, NOT the shared constant: comparing the
      // rendered icon to the same constant the widget is built from would pass
      // for any value, so it could not catch the size drifting back to
      // Material's 24px default.
      expect(icon.size, 18.0,
          reason: '${entry.key} must not restate the size on its own');
    });

    testWidgets('${entry.key} hides the crosshair without a current item',
        (tester) async {
      // The shared helper keeps V1's original gating: a data source with no
      // current item gets no button, in every layout.
      final ds = FakePagedBrowserDataSource(supportsCurrent: false);
      await tester.pumpWidget(StoreScope(
        child: MaterialApp(
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
                toolbarLayout: entry.value,
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.my_location), findsNothing);
    });
  }
}
