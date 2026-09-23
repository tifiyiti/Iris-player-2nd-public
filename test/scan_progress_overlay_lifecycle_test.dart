import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/scan/model/recursive_scan_state.dart';
import 'package:iris/features/media_library/scan/store/recursive_scan_store.dart';
import 'package:iris/features/media_library/scan/view/scan_progress_overlay.dart';
import 'package:iris/l10n/app_localizations.dart';

/// Lifecycle contract for the scan-progress [OverlayEntry].
///
/// WHY: an overlay entry that stays mounted while idle (its builder returning
/// `SizedBox.shrink()`) puts a zero-size, structurally-swapping render object
/// into the root Overlay. The mouse tracker's hit test can reach that child
/// before it is laid out, throwing `Cannot hit test a render box that has never
/// been laid out`, which then escapes `MouseTracker._deviceUpdatePhase` and
/// permanently poisons `_debugDuringDeviceUpdate` (frame-rate assertion storm,
/// dead hover/cursor).
///
/// The entry must therefore exist ONLY while a scan is active; when idle the
/// Overlay must be restored to its baseline (no lingering zero-size entry).
///
/// Store mutations are intentionally NOT awaited: their state transitions are
/// synchronous `set()` calls, while the KV `save()` rides a platform channel
/// that never resolves inside the test binding's FakeAsync zone.
void main() {
  setUp(() {
    useRecursiveScanStore().resetScan();
    ScanProgressOverlayManager.debugEntryMountedForTest = false;
  });

  testWidgets('scan overlay entry is mounted only while a scan is active',
      (tester) async {
    final store = useRecursiveScanStore();

    await tester.pumpWidget(const MaterialApp(
      locale: Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: ScanProgressOverlayManager()),
    ));
    await tester.pumpAndSettle();

    expect(ScanProgressOverlayManager.debugEntryMountedForTest, isFalse,
        reason: 'idle: no overlay entry may linger (this is the hazard)');

    store.startScan(storageId: 's1', depthPaths: {0: ['C:/a']});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(ScanProgressOverlayManager.debugEntryMountedForTest, isTrue,
        reason: 'scanning: the progress panel must be mounted');
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    store.completeScan();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Closing in'), findsOneWidget,
        reason: 'countdown must render so the removal assertion is meaningful');

    for (var i = 0; i < 40 && store.state.phase != ScanPhase.idle; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(store.state.phase, ScanPhase.idle);
    await tester.pump();

    expect(ScanProgressOverlayManager.debugEntryMountedForTest, isFalse,
        reason: 'idle again: the entry must be removed, not shrunk to zero');
    expect(find.textContaining('Closing in'), findsNothing);

    expect(tester.takeException(), isNull,
        reason: 'no assertion may fire across the lifecycle');
  });

  testWidgets('hover hit tests stay clean once the scan overlay is removed',
      (tester) async {
    final store = useRecursiveScanStore();

    await tester.pumpWidget(const MaterialApp(
      locale: Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: ScanProgressOverlayManager()),
    ));
    await tester.pumpAndSettle();

    store.startScan(storageId: 's1', depthPaths: {0: ['C:/a']});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    store.completeScan();
    await tester.pump();
    for (var i = 0; i < 40 && store.state.phase != ScanPhase.idle; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump();

    // Mouse hover after teardown — the exact gesture that used to detonate the
    // mouse-tracker assertion via a not-yet-laid-out overlay child.
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(const Offset(200, 200));
    await tester.pump();
    await gesture.moveTo(const Offset(210, 210));
    await tester.pump();

    expect(tester.takeException(), isNull,
        reason: 'hover over a removed scan overlay must not throw');
  });
}
