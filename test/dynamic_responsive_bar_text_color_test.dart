import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/paginated_browser/data_source/mock_browser_data_source.dart';
import 'package:iris/features/paginated_browser/paginated_browser_controller.dart';
import 'package:iris/features/paginated_browser/widgets/dynamic_responsive_bar.dart';
import 'package:iris/l10n/app_localizations.dart';

void main() {
  // Regression: the page counter ("x/y") lives in the toolbar, which is NOT
  // inside the browser list's `Material`. A bare `Text` therefore inherited the
  // outermost `Material`'s `DefaultTextStyle` (app theme) instead of the
  // toolbar's own theme — black on the dark docked panel, i.e. invisible.
  testWidgets(
      'page counter takes an explicit color from the toolbar theme, never the '
      'ambient DefaultTextStyle', (tester) async {
    final controller = PaginatedBrowserController<MockItemEntity>();
    final dataSource = MockBrowserDataSource();
    final darkTheme = ThemeData.dark();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // Light app theme forces a dark ambient DefaultTextStyle (the bug's
        // precondition); the toolbar itself is dark.
        theme: ThemeData.light(),
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 120,
            child: Theme(
              data: darkTheme,
              child: DynamicResponsiveBar<MockItemEntity>(
                controller: controller,
                dataSource: dataSource,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final counters = tester.widgetList<Text>(
      find.byWidgetPredicate((w) =>
          w is Text &&
          w.data != null &&
          RegExp(r'^\d+/\d+$').hasMatch(w.data!)),
    );
    expect(counters, isNotEmpty,
        reason: 'items-per-page chip and page counter both render x/y');
    for (final counter in counters) {
      expect(counter.style?.color, isNotNull,
          reason: 'counter "$counter.data" must set an explicit color');
    }
  });
}
