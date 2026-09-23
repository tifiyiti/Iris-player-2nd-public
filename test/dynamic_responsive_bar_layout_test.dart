import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/paginated_browser/data_source/mock_browser_data_source.dart';
import 'package:iris/features/paginated_browser/paginated_browser_controller.dart';
import 'package:iris/features/paginated_browser/widgets/dynamic_responsive_bar.dart';
import 'package:iris/l10n/app_localizations.dart';

void main() {
  // Forces the tier-2 (two-row) layout: width 400 sits between the two-row
  // requirement (maxRowWidth ~316) and the one-row requirement
  // (oneRowWidth ~524) of the responsive bar.
  Future<void> pumpTwoRowBar(WidgetTester tester) async {
    final controller = PaginatedBrowserController<MockItemEntity>();
    final dataSource = MockBrowserDataSource();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: 400,
              height: 120,
              child: DynamicResponsiveBar<MockItemEntity>(
                controller: controller,
                dataSource: dataSource,
              ),
            ),
          ),
        ),
      ),
    );
    // Deferred l10n delegates load async — settle before inspecting.
    await tester.pumpAndSettle();
  }

  Finder _bar() => find.byWidgetPredicate((w) => w is DynamicResponsiveBar);

  List<Widget> firstRowChildren(WidgetTester tester) {
    final row = tester.widgetList<Row>(
      find.descendant(
        of: _bar(),
        matching: find.byType(Row),
      ),
    ).first;
    return row.children;
  }

  testWidgets('two-row layout renders exactly two rows and the search button',
      (tester) async {
    await pumpTwoRowBar(tester);

    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(
      find.descendant(of: _bar(), matching: find.byType(Row)),
      findsNWidgets(3), // row 1 + row 2 + the page-nav row inside row 2
    );
  });

  testWidgets('two-row layout: search button immediately follows the items-per-page'
      ' chip as the 2nd element of row 1 (v9-D1)', (tester) async {
    await pumpTwoRowBar(tester);

    final row1 = firstRowChildren(tester);
    final searchIndex = row1.indexWhere((c) =>
        c is IconButton && (c.icon as Icon?)?.icon == Icons.search);
    expect(searchIndex, isNot(-1), reason: 'search button should be in row 1');
    // The chip (perPageTotal) is the first element; search is right after it.
    expect(searchIndex, 1,
        reason: 'search must be the 2nd element, right after the chip');
    expect(row1[searchIndex - 1], isA<ConstrainedBox>(),
        reason: 'the element before search must be the items-per-page chip');
    expect(row1.contains(const Spacer()), isFalse,
        reason: 'no Spacer is involved in the v9 unified placement');
  });

  testWidgets('items-per-page chip has a fixed width regardless of the total '
      'digit count (v9-D2)', (tester) async {
    await pumpTwoRowBar(tester);

    final row1 = firstRowChildren(tester);
    final chip = row1.first;
    expect(chip, isA<ConstrainedBox>());
    final constraints = (chip as ConstrainedBox).constraints;
    // Tight width: the chip must not expand/shrink as the total count changes.
    expect(constraints.maxWidth, 64);
    expect(constraints.minWidth, constraints.maxWidth);
  });
}
