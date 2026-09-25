import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/scan/model/recursive_scan_state.dart';
import 'package:iris/features/media_library/scan/store/recursive_scan_store.dart';
import 'package:iris/features/media_library/scan/view/scan_progress_overlay.dart';
import 'package:iris/features/scenario_playback/scan/model/scenario_source_refresh_state.dart';
import 'package:iris/features/scenario_playback/scan/service/scenario_source_refresh_service.dart';
import 'package:iris/features/scenario_playback/scan/store/scenario_source_refresh_store.dart';
import 'package:iris/features/scenario_playback/scan/view/scenario_source_refresh_overlay.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/storages/file_list_result.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_storage_store.dart';
import 'package:iris/utils/get_localizations.dart';

/// Regression: a completed scenario-source refresh used to show up to THREE
/// completion surfaces at once — the generic scan bar's auto-close countdown,
/// the lingering batch panel, and the summary dialog. The session must tear
/// both progress surfaces down BEFORE showing the single summary dialog.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  late AppDatabase db;

  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory());
    DbModule.init(db);
    useAppStore();
    await useAppStore().initialized;
    useStorageStore();
    await useStorageStore().initialized;
    usePlaybackScenarioStore();
    await usePlaybackScenarioStore().initialized;
    useRecursiveScanStore();
    await useRecursiveScanStore().initialized;
  });

  tearDownAll(() => db.close());

  setUp(() async {
    useScenarioSourceRefreshStore().reset();
    useRecursiveScanStore().setOverlaySuppressed(false);
    await useRecursiveScanStore().resetScan();
    ScenarioSourceRefreshOverlayManager.debugEntryMountedForTest = false;
    ScanProgressOverlayManager.debugEntryMountedForTest = false;
  });

  testWidgets(
      'a finished refresh shows ONE summary dialog and no lingering progress UI',
      (tester) async {
    const storageId = 'st-single-surface';
    await useStorageStore().addStorage(Storage.local(
      id: storageId,
      type: StorageType.internal,
      name: 'Local',
      basePath: const ['root'],
    ));

    final scenarioStore = usePlaybackScenarioStore();
    final scenario = await scenarioStore.ensureSystemPlayingScenario();
    await DbModule.scenarioRepo.clearSources(scenario.id);
    await DbModule.scenarioRepo.addSource(
      scenarioId: scenario.id,
      storageId: storageId,
      path: 'movies',
      recursive: true,
    );

    late String scanStartLabel;
    late String summaryTitle;

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Stack(
          children: [
            const ScanProgressOverlayManager(),
            const ScenarioSourceRefreshOverlayManager(),
            Builder(builder: (context) {
              final t = getLocalizations(context);
              scanStartLabel = t.scan_start;
              summaryTitle = t.scn_scan_summary_title;
              return Center(
                child: TextButton(
                  onPressed: () {
                    ScenarioSourceRefreshService(
                      // Never touch the real filesystem: every directory lists
                      // as successfully empty.
                      listDir: (_, __) async => FileListResult.empty,
                    ).refreshScenarioSources(
                      context: context,
                      scenarioId: scenario.id,
                    );
                  },
                  child: const Text('refresh'),
                ),
              );
            }),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('refresh'));
    // Let the refresh's real async work (DB reads, preflight) advance before
    // asserting on the dialog it eventually pushes.
    await _settleUntil(
        tester, () => find.text(scanStartLabel).evaluate().isNotEmpty);
    await tester.pumpAndSettle(); // scan-options dialog
    expect(find.text(scanStartLabel), findsOneWidget);

    await tester.tap(find.text(scanStartLabel));
    // Drive the scan (real async: DFS + aggregates + convergence) to its end.
    await _settleUntil(
        tester, () => find.text(summaryTitle).evaluate().isNotEmpty);
    await tester.pumpAndSettle(); // scan + single summary dialog

    expect(find.text(summaryTitle), findsOneWidget,
        reason: 'exactly one completion summary may be shown');

    // Both progress surfaces are idle before the dialog is presented, so
    // neither can stack under it (no auto-close countdown, no batch panel).
    expect(useRecursiveScanStore().state.phase, ScanPhase.idle);
    expect(useScenarioSourceRefreshStore().state.phase,
        ScenarioSourceRefreshPhase.idle);
    expect(ScanProgressOverlayManager.debugEntryMountedForTest, isFalse,
        reason: 'the generic scan bar must not mount behind the summary');
    expect(
        ScenarioSourceRefreshOverlayManager.debugEntryMountedForTest, isFalse,
        reason: 'the batch panel must be torn down before the summary');
  });
}

/// Drives the tree until [done] is true: advances the FAKE clock (the scan is
/// started from a UI callback, so its `Future.delayed` yields are fake timers)
/// AND lets real async work (drift, filesystem) progress via [WidgetTester.runAsync].
Future<void> _settleUntil(
  WidgetTester tester,
  bool Function() done, {
  int tries = 200,
}) async {
  for (var i = 0; i < tries; i++) {
    if (done()) return;
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}
