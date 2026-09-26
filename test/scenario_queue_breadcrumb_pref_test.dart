import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/paginated_browser/models/browser_toolbar_layout.dart';
import 'package:iris/features/paginated_browser/paginated_browser_controller.dart';
import 'package:iris/features/paginated_browser/paginated_browser_page.dart';
import 'package:iris/l10n/app_localizations.dart';

import 'helpers/fake_paged_browser_data_source.dart';

/// The scenario queue's breadcrumb row is driven by ONE shared preference
/// (`AppState.scenarioQueueShowBreadcrumb`, default hidden) that ALL queue
/// layouts honour. V1 does not own a toggle for it — the checkbox lives in the
/// overflow menu of the layouts that have one — so the only place the coupling
/// can break is the page, and this test pins it there for every toolbar layout.
///
/// V3 is the interesting one: it has no bottom section at all, so the row moved
/// to the TOP of the page, and a row that silently stopped rendering there would
/// look exactly like the preference being ignored.
void main() {
  const crumbs = ['My Scenario', 'Kids'];

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

  Future<void> pump(
    WidgetTester tester,
    BrowserToolbarLayout layout, {
    required bool showBreadcrumb,
  }) async {
    await tester.pumpWidget(wrap(
      PaginatedBrowserPage<String>(
        dataSource: FakePagedBrowserDataSource(breadcrumbs: crumbs),
        controller: PaginatedBrowserController<String>(),
        onClose: () {},
        showHomePage: false,
        showBackButton: false,
        toolbarLayout: layout,
        showBreadcrumb: showBreadcrumb,
      ),
    ));
    await tester.pumpAndSettle();
  }

  for (final entry in <String, BrowserToolbarLayout>{
    'V1': BrowserToolbarLayout.responsive,
    'V2': BrowserToolbarLayout.compactSingleLine,
    'V3': BrowserToolbarLayout.floatingGrid,
  }.entries) {
    group('${entry.key} follows the breadcrumb preference', () {
      testWidgets('hidden when the pref is off (the default)', (tester) async {
        await pump(tester, entry.value, showBreadcrumb: false);
        expect(find.text('My Scenario'), findsNothing);
        expect(find.text('Kids'), findsNothing);
      });

      testWidgets('shown when the pref is on', (tester) async {
        await pump(tester, entry.value, showBreadcrumb: true);
        expect(find.text('My Scenario'), findsOneWidget);
        expect(find.text('Kids'), findsOneWidget);
      });
    });
  }

  testWidgets('the default keeps the breadcrumb (browsers that do not opt out)',
      (tester) async {
    await tester.pumpWidget(wrap(
      PaginatedBrowserPage<String>(
        dataSource: FakePagedBrowserDataSource(breadcrumbs: crumbs),
        controller: PaginatedBrowserController<String>(),
        onClose: () {},
        showHomePage: false,
        showBackButton: false,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('My Scenario'), findsOneWidget);
  });
}
