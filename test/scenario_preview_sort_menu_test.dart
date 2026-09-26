import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';
import 'package:iris/features/scenario_playback/view/sources/paged_scenario_preview_data_source.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';

/// The resolve-preview's sort menu is hosted by the same generic browser as the
/// play queue, so it inherits the same contract: the WHOLE row toggles, and
/// toggling must not take the hosting page down with the menu.
void main() {
  setUpAll(() async {
    final db = AppDatabase(NativeDatabase.memory());
    DbModule.init(db);
    usePlaybackScenarioStore();
    await usePlaybackScenarioStore().initialized;
    await runZonedGuarded(() async {
      usePlayQueueStore();
      await usePlayQueueStore().initialized;
      useAppStore();
      await useAppStore().initialized;
    }, (Object e, StackTrace st) {});
  });

  testWidgets('a checkbox row toggles without popping the page that owns the menu',
      (tester) async {
    // `PopupMenuItem.handleTap` pops the MENU route before it runs onTap, so the
    // explicit `Navigator.pop(pageContext)` that followed the toggle popped the
    // route UNDER the menu. The preview is swapped in place inside the
    // management page, so that page vanished on every checkbox tap.
    await tester.pump(const Duration(milliseconds: 100));
    final store = usePlaybackScenarioStore();
    final created = await DbModule.scenarioRepo.createScenario(name: 'P');
    await store.refreshScenarios();

    final ds = PagedScenarioPreviewDataSource(
      scenarioId: created.id,
      onExitPreview: () {},
    );
    addTearDown(ds.dispose);

    // Same font-metric workaround as the queue menu: the test font makes the
    // 280px-wide popup overflow its checkbox rows.
    tester.platformDispatcher.textScaleFactorTestValue = 0.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final pops = _PopRecorder();
    await tester.pumpWidget(
      StoreScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          navigatorObservers: [pops],
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      settings: const RouteSettings(name: kPreviewHostRoute),
                      builder: (_) => Scaffold(
                        body: Builder(
                          builder: (context) => ds.buildSortMenu(context),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('open preview'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open preview'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.sort_rounded));
    await tester.pumpAndSettle();

    // The row BODY, not the checkbox: the whole row is the tap target.
    await tester.tap(find.text('Dedupe'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));

    expect(pops.popped, isNot(contains(kPreviewHostRoute)),
        reason: 'the menu closes itself; a second pop takes the page with it');
    expect(find.byIcon(Icons.sort_rounded), findsOneWidget,
        reason: 'the hosting page must survive its own sort menu');
  });
}

const kPreviewHostRoute = 'preview-host';

/// Records which routes leave the navigator, so a test can tell the menu's own
/// pop (expected) from a pop of the page underneath it (the regression).
class _PopRecorder extends NavigatorObserver {
  final popped = <String?>[];

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popped.add(route.settings.name);
  }
}
