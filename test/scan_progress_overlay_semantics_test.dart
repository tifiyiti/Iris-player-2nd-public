import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/scan/model/recursive_scan_state.dart';
import 'package:iris/features/media_library/scan/store/recursive_scan_store.dart';
import 'package:iris/features/media_library/scan/view/scan_progress_overlay.dart';
import 'package:iris/l10n/app_localizations.dart';

/// Windows AXTree-corruption mitigation (flutter/flutter#182444 family).
///
/// The scan overlay is a draggable transient feedback panel mounted as a
/// Navigator OverlayEntry. Two hazards for the engine's accessibility
/// bridge:
///  1. its progress bar / status path / percent / countdown texts mutate
///     continuously (during the countdown: 10 Hz) — every mutation is a
///     semantics update that feeds the AXTree pipeline while carrying zero
///     assistive value;
///  2. an auto-close timer that rebuilt the entry ~1000x/s (1 ms periodic)
///     turned the panel into a semantics update flood.
///
/// Contract: the ticking texts stay OUT of the semantics tree, the countdown
/// still renders, and the auto-close completes exactly once.
///
/// Store mutations are intentionally NOT awaited: their state transitions
/// are synchronous `set()` calls, while the KV `save()` rides a platform
/// channel that never resolves inside the test binding's FakeAsync zone.
_Snapshot _snapshot() {
  var total = 0;
  final labels = <String>[];
  void visit(SemanticsNode node) {
    total++;
    if (node.label.trim().isNotEmpty) labels.add(node.label);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  final root = RendererBinding.instance.renderViews.first.owner
      ?.semanticsOwner
      ?.rootSemanticsNode;
  if (root != null) visit(root);
  return _Snapshot(total, labels);
}

class _Snapshot {
  _Snapshot(this.total, this.labels);
  final int total;
  final List<String> labels;

  @override
  String toString() => 'total=$total labels=$labels';
}

void main() {
  testWidgets(
      'scan overlay ticking texts stay out of semantics and auto-close settles',
      (tester) async {
    final handle = tester.ensureSemantics();
    final store = useRecursiveScanStore();
    store.resetScan();

    await tester.pumpWidget(const MaterialApp(
      locale: Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: ScanProgressOverlayManager()),
    ));
    await tester.pumpAndSettle();
    final base = _snapshot();

    store.startScan(storageId: 's1', depthPaths: {0: ['C:/a']});
    // NOTE: no pumpAndSettle here — the scanning phase shows an
    // indeterminate LinearProgressIndicator whose animation never settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Elapsed'), findsOneWidget,
        reason: 'elapsed/ETA readout must actually render for the semantics '
            'assertion below to bite');
    final scanning = _snapshot();
    expect(scanning.labels.where((l) => !base.labels.contains(l)), isEmpty,
        reason: 'scanning status/percent must not announce '
            '(base=$base scanning=$scanning)');

    store.completeScan();
    // Frame 1 runs the listener's post-frame `markNeedsBuild`; frame 2
    // actually rebuilds the entry with the countdown.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Closing in'), findsOneWidget,
        reason: 'countdown must actually render for this assertion to bite');
    final closing = _snapshot();
    expect(closing.labels.where((l) => !base.labels.contains(l)), isEmpty,
        reason: 'countdown texts must not announce '
            '(base=$base closing=$closing)');

    // pumpAndSettle is unreliable across the 100 ms tick boundary (the frame
    // schedule check can land between ticks), so drain the countdown with a
    // bounded manual pump loop — 2.5 s = 25 ticks, +margin.
    for (var i = 0; i < 40 && store.state.phase != ScanPhase.idle; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(store.state.phase, ScanPhase.idle,
        reason: 'auto-close must complete exactly once after the delay');

    handle.dispose();
  });
}
