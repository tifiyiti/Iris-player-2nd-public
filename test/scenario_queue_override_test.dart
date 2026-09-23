import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/scenario_playback/view/coordinator/scenario_browser.dart';
import 'package:iris/features/scenario_playback/view/coordinator/scenario_browser_store.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/widgets/popup.dart';

/// Part C regression suite: the playing-queue override context.
///
/// Queue-owned Manage is fully independent from StoragesDb (one source of truth
/// via ScenarioRepo). Both floating popup and docked panel use the local
/// [ScenarioBrowserStore.queueOverrideMode] so the manager renders INSIDE the
/// same popup/panel — never touches [MediaLibBrowserStore] / StoragesDb.
void main() {
  group('ScenarioBrowserStore queueOverrideMode', () {
    test('defaults to null (override inactive)', () {
      final store = ScenarioBrowserStore();
      expect(store.queueOverrideMode, isNull);
      expect(store.queueOverrideActive, isFalse);
    });

    test('setQueueOverrideMode activates and updates the mode', () {
      final store = ScenarioBrowserStore();
      store.setQueueOverrideMode(ScenarioBrowserMode.search);
      expect(store.queueOverrideActive, isTrue);
      expect(store.state.queueOverrideMode, ScenarioBrowserMode.search);
      store.setQueueOverrideMode(ScenarioBrowserMode.sources);
      expect(store.queueOverrideActive, isTrue);
      expect(store.state.queueOverrideMode, ScenarioBrowserMode.sources);
    });

    test('resetQueueOverride deactivates', () {
      final store = ScenarioBrowserStore();
      store.setQueueOverrideMode(ScenarioBrowserMode.sources);
      store.resetQueueOverride();
      expect(store.queueOverrideActive, isFalse);
      expect(store.state.queueOverrideMode, isNull);
    });
  });

  group('resolveManageFromQueueTarget', () {
    test('floating popup route (canPop) -> inPlaceOverridePanel (queue-owned)', () {
      expect(
        resolveManageFromQueueTarget(canPop: true),
        ManageFromQueueTarget.inPlaceOverridePanel,
      );
    });

    test('docked in-tree panel (root route) -> inPlaceOverridePanel', () {
      expect(
        resolveManageFromQueueTarget(canPop: false),
        ManageFromQueueTarget.inPlaceOverridePanel,
      );
    });
  });

  group('openManagerFromQueue docked branch', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await DbModule.init(db);
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets(
        'switches the override panel to the manager and never touches the '
        'navigator when the queue is not a route', (tester) async {
      final observer = _NavigatorObserver();
      final store = useScenarioBrowserStore();
      await tester.pumpWidget(MaterialApp(
        navigatorObservers: [observer],
        home: Builder(builder: (context) {
          return Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => openManagerFromQueue(
                  context,
                  scenarioId: 'sc-1',
                  direction: PopupDirection.right,
                ),
                child: const Text('manage'),
              ),
            ),
          );
        }),
      ));
      await tester.pump();

      // Baseline: MaterialApp's initial-route push already happened.
      final pushedBefore = observer.pushedCount;
      final replacedBefore = observer.replacedCount;

      await tester.tap(find.text('manage'));
      await tester.pump();
      await tester.pump();

      // Root route untouched — queue-owned manage never touches StoragesDb.
      expect(observer.pushedCount, pushedBefore);
      expect(observer.replacedCount, replacedBefore);
      // Manager renders via the local override (independent from StoragesDb).
      expect(store.queueOverrideActive, isTrue);
      expect(store.state.queueOverrideMode, ScenarioBrowserMode.sources);
      // One-shot back seed is legacy (floating StoragesDb branch) — unused now.
      expect(store.consumeManagerEnteredFromQueue(), isFalse);
      // Queue-owned manage must NOT pollute persisted manager mode.
      expect(store.state.mode, ScenarioBrowserMode.queue);
    });
  });
}

class _NavigatorObserver extends NavigatorObserver {
  int pushedCount = 0;
  int replacedCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedCount++;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    replacedCount++;
  }
}
