import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/media_library/model/enum/basic_enum.dart';
import 'package:iris/features/scenario_playback/model/domain/scenario.dart';
import 'package:iris/features/scenario_playback/model/enum/duplicate_policy.dart';
import 'package:iris/features/scenario_playback/model/enum/scenario_sort_field.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';
import 'package:iris/features/scenario_playback/view/queue/paged_scenario_media_data_source.dart';
import 'package:iris/features/scenario_playback/view/sort/scenario_order_choice.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';

/// The queue's order menu must mark the field the user last chose, even when
/// that field IS the captured queue-generation rule.
///
/// Regression (reported as "click Name but it still shows Original asc/desc"):
/// every browse-page override records the page's sort — usually NAME — as
/// `Scenario.originalSortField`, and the menu used to give that captured rule
/// priority over the field. Clicking 名称 therefore only flipped the arrow while
/// the highlighted row stayed 原始顺序, i.e. the click looked dead.
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

  /// A queue exactly as a browse-page override leaves it: sorted by name, with
  /// name captured as the generation rule.
  Future<Scenario> seedNameCapturedQueue() async {
    final store = usePlaybackScenarioStore();
    final created = await DbModule.scenarioRepo.createScenario(name: 'Q');
    final scenario = created.copyWith(
      sortField: ScenarioSortField.name,
      sortDirection: SortDirection.asc,
      originalSortField: ScenarioSortField.name,
    );
    await DbModule.scenarioRepo.updateScenario(scenario);
    await store.refreshScenarios();
    await store.setActiveScenario(scenario.id);
    return scenario;
  }

  Finder rowOf(String label) => find.ancestor(
        of: find.text(label),
        matching: find.byType(PopupMenuItem<ScenarioOrderChoice>),
      );

  /// The test font is a fixed-width square per glyph, so labels measure ~2x
  /// their real width and the menu's own 280px width cap makes the checkbox
  /// rows overflow — a font-metric artifact, not a layout bug. Shrink the text
  /// scale so the popup measures like the real thing.
  void useRealisticTextScale(WidgetTester tester) {
    tester.platformDispatcher.textScaleFactorTestValue = 0.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  Future<void> openMenu(WidgetTester tester, String scenarioId) async {
    final ds = PagedScenarioMediaDataSource(scenarioId: scenarioId);
    addTearDown(ds.dispose);

    useRealisticTextScale(tester);

    await tester.pumpWidget(
      StoreScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(builder: (context) => ds.buildSortMenu(context)),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byIcon(Icons.sort_rounded));
    await tester.pumpAndSettle();
  }

  /// Opens the menu with the queue hosted by a SECOND (pushed) route, which is
  /// how it is really hosted: a floating popup (`showPopup` pushes a route) or
  /// the side dock. A root-route host cannot catch a stray pop — popping it only
  /// empties the tree, which nothing here would notice.
  Future<void> openMenuOnPushedRoute(
    WidgetTester tester,
    String scenarioId,
    _PopRecorder pops,
  ) async {
    final ds = PagedScenarioMediaDataSource(scenarioId: scenarioId);
    addTearDown(ds.dispose);

    useRealisticTextScale(tester);

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
                      settings: const RouteSettings(name: kQueueHostRoute),
                      builder: (_) => Scaffold(
                        body: Builder(
                          builder: (context) => ds.buildSortMenu(context),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('open queue'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open queue'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.sort_rounded), findsOneWidget,
        reason: 'sanity: the pushed route really hosts the queue');

    await tester.tap(find.byIcon(Icons.sort_rounded));
    await tester.pumpAndSettle();
  }

  testWidgets('a name-captured queue highlights Name, not Original',
      (tester) async {
    // Elapse fake time first so drift executor deliveries complete for the
    // DB awaits below.
    await tester.pump(const Duration(milliseconds: 100));
    final scenario = await seedNameCapturedQueue();
    await openMenu(tester, scenario.id);

    // The captured rule is still reachable, and now names what it restores.
    expect(find.text('Original (Name)'), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);

    // Exactly ONE row is active, and it is the field the user chose.
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    expect(
      find.descendant(
          of: rowOf('Name'), matching: find.byIcon(Icons.arrow_upward)),
      findsOneWidget,
    );
    expect(
      find.descendant(
          of: rowOf('Original (Name)'), matching: find.byType(Icon)),
      findsNothing,
    );
  });

  testWidgets('re-clicking the active field flips the arrow in place',
      (tester) async {
    await tester.pump(const Duration(milliseconds: 100));
    final scenario = await seedNameCapturedQueue();
    await openMenu(tester, scenario.id);

    await tester.tap(find.text('Name'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));

    // The flip is a scenario write, and the menu keeps pointing at Name.
    final updated = await DbModule.scenarioRepo.getScenario(scenario.id);
    expect(updated!.sortField, ScenarioSortField.name);
    expect(updated.sortDirection, SortDirection.desc);

    await openMenu(tester, scenario.id);
    expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    expect(
      find.descendant(
          of: rowOf('Name'), matching: find.byIcon(Icons.arrow_downward)),
      findsOneWidget,
    );
  });

  testWidgets('tapping the checkbox ROW toggles it, not just the box',
      (tester) async {
    // The row is the tap target, exactly like the V2/V3 overflow menu rows: the
    // checkbox only MIRRORS the state. It used to hang the toggle off
    // `Checkbox.onChanged` alone, so a tap anywhere on the row body did nothing
    // at all — a dead strip as wide as the label.
    await tester.pump(const Duration(milliseconds: 100));
    final scenario = await seedNameCapturedQueue();
    await openMenu(tester, scenario.id);

    expect(
      tester
          .widget<Checkbox>(
            find.descendant(
              of: rowOf('Dedupe'),
              matching: find.byType(Checkbox),
            ),
          )
          .value,
      isFalse,
    );

    // The label text, i.e. the row body — deliberately NOT the checkbox itself.
    await tester.tap(find.text('Dedupe'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));

    final updated = await DbModule.scenarioRepo.getScenario(scenario.id);
    expect(updated!.duplicatePolicy, DuplicatePolicy.deduplicate,
        reason: 'a tap on the row must toggle, like every other menu row');
  });

  testWidgets('toggling a checkbox row does not pop the page that owns the menu',
      (tester) async {
    // The regression: `PopupMenuItem.handleTap` pops the MENU route and only
    // then runs onTap, so the explicit `Navigator.pop(pageContext)` that used to
    // follow the toggle hit the route UNDER the menu — the floating queue popup
    // closed with it, and in the side dock (not a route at all) it popped the
    // host page straight off the navigator. Only a second route can prove it.
    await tester.pump(const Duration(milliseconds: 100));
    final scenario = await seedNameCapturedQueue();
    final pops = _PopRecorder();
    await openMenuOnPushedRoute(tester, scenario.id, pops);

    await tester.tap(find.text('Dedupe'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));

    expect(pops.popped, isNot(contains(kQueueHostRoute)),
        reason: 'the menu closes itself; a second pop takes the page with it');
    expect(find.byIcon(Icons.sort_rounded), findsOneWidget,
        reason: 'the hosting page must survive its own sort menu');

    // The toggle itself still happened — the fix removes the stray pop, not
    // the write.
    final updated = await DbModule.scenarioRepo.getScenario(scenario.id);
    expect(updated!.duplicatePolicy, DuplicatePolicy.deduplicate);
  });

  testWidgets('a null captured rule disables Original and keeps it unmarked',
      (tester) async {
    await tester.pump(const Duration(milliseconds: 100));
    final store = usePlaybackScenarioStore();
    final created = await DbModule.scenarioRepo.createScenario(name: 'Plain');
    final scenario = created.copyWith(
      sortField: ScenarioSortField.sizeInBytes,
      originalSortField: null,
    );
    await DbModule.scenarioRepo.updateScenario(scenario);
    await store.refreshScenarios();
    await store.setActiveScenario(scenario.id);

    await openMenu(tester, scenario.id);

    // No captured rule to name: the base label stays, disabled.
    expect(find.text('Original'), findsOneWidget);
    final item = tester.widget<PopupMenuItem<ScenarioOrderChoice>>(
      find.ancestor(
        of: find.text('Original'),
        matching: find.byType(PopupMenuItem<ScenarioOrderChoice>),
      ),
    );
    expect(item.enabled, isFalse);
    expect(
      find.descendant(of: rowOf('Original'), matching: find.byType(Icon)),
      findsNothing,
    );
    expect(
      find.descendant(
          of: rowOf('Size'), matching: find.byIcon(Icons.arrow_upward)),
      findsOneWidget,
      reason: 'a non-name field is marked the same way',
    );
  });
}

/// Route name of the page that hosts the queue in [openMenuOnPushedRoute].
const kQueueHostRoute = 'queue-host';

/// Records which routes leave the navigator, so a test can tell the menu's own
/// pop (expected) from a pop of the page underneath it (the regression).
class _PopRecorder extends NavigatorObserver {
  final popped = <String?>[];

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popped.add(route.settings.name);
  }
}
