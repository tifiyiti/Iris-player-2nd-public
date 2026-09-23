import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/scan/store/recursive_scan_store.dart';
import 'package:iris/features/scenario_playback/scan/model/scenario_source_refresh_state.dart';
import 'package:iris/features/scenario_playback/scan/store/scenario_source_refresh_store.dart';
import 'package:iris/features/scenario_playback/scan/view/scenario_source_refresh_overlay.dart';
import 'package:iris/l10n/app_localizations.dart';

/// Pause/resume contract for the scenario-source refresh batch overlay.
///
/// WHY: the pause button must read and write the SAME pause flag. The single
/// source of truth is [RecursiveScanStore.paused] — the flag the
/// [RecursiveScanService] loop actually blocks on (`_waitIfPaused`). A batch
/// overlay that reads its own (never-written) flag shows `pause` forever and
/// can only ever call `pauseScan()`, so a paused run can never be resumed.
///
/// Store mutations are intentionally NOT awaited: their state transitions are
/// synchronous `set()` calls.
void main() {
  setUp(() {
    useScenarioSourceRefreshStore().reset();
    ScenarioSourceRefreshOverlayManager.debugEntryMountedForTest = false;
    final scanStore = useRecursiveScanStore();
    if (scanStore.state.paused) scanStore.resumeScan();
  });

  Future<void> pumpOverlay(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: ScenarioSourceRefreshOverlayManager()),
    ));
    await tester.pumpAndSettle();
  }

  void startOneUnitBatch() {
    useScenarioSourceRefreshStore().start([
      const ScenarioSourceRefreshUnit(
        storageId: 's1',
        storageName: 'disk',
        weight: 1,
      ),
    ]);
  }

  testWidgets('pause button toggles to resume and back (single truth)',
      (tester) async {
    await pumpOverlay(tester);
    startOneUnitBatch();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(ScenarioSourceRefreshOverlayManager.debugEntryMountedForTest, isTrue,
        reason: 'running batch must mount its overlay');
    expect(find.widgetWithIcon(IconButton, Icons.pause), findsOneWidget,
        reason: 'not paused: the button must offer pause');
    expect(find.widgetWithIcon(IconButton, Icons.play_arrow), findsNothing);

    // First tap pauses the underlying scan; the SAME flag drives the icon,
    // so it must flip to "resume".
    await tester.tap(find.widgetWithIcon(IconButton, Icons.pause));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(useRecursiveScanStore().state.paused, isTrue);
    expect(find.widgetWithIcon(IconButton, Icons.play_arrow), findsOneWidget,
        reason: 'paused: the button must offer resume, not pause again');
    expect(find.widgetWithIcon(IconButton, Icons.pause), findsNothing);
    expect(find.text('Paused'), findsOneWidget,
        reason: 'paused status text must be shown');

    // Second tap resumes.
    await tester.tap(find.widgetWithIcon(IconButton, Icons.play_arrow));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(useRecursiveScanStore().state.paused, isFalse);
    expect(find.widgetWithIcon(IconButton, Icons.pause), findsOneWidget,
        reason: 'resumed: the button must offer pause again');

    expect(tester.takeException(), isNull);
  });

  testWidgets('external pause is reflected without tapping (listener held)',
      (tester) async {
    await pumpOverlay(tester);
    startOneUnitBatch();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    useRecursiveScanStore().pauseScan();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.widgetWithIcon(IconButton, Icons.play_arrow), findsOneWidget,
        reason: 'a pause issued elsewhere must still flip the batch icon');

    expect(tester.takeException(), isNull);
  });
}
