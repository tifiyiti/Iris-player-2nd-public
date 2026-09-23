import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/main.dart'
    show debugSuppressWindowsSemanticsOverride, wrapPlatformSemantics;

/// Windows-only semantics suppression — the AXTree-corruption kill-switch.
///
/// WHY (flutter/flutter #182444 / #190344 / #98099 family, unfixed in
/// 3.44.x): the Windows engine's accessibility bridge corrupts its private
/// AXTree cache on structural semantics batches (subtree mount/unmount:
/// popup open/close, tab swap, route replacement). Session evidence
/// (2026-08): a legitimate 35-node route-subtree swap seeded the
/// corruption; the next benign update detonated it; every later commit then
/// re-failed with "Nodes left pending by the update: 35" for the whole
/// session. Dart has no resync channel for the engine cache, so the only
/// app-side guarantee is an EMPTY semantics tree: the engine receives one
/// valid root-only update and never another.
///
/// Contract: with the suppression ON (Windows production), the semantics
/// tree contributes NO labeled nodes; with it OFF (every other platform /
/// future re-enable path), labels pass through untouched.
class _Snapshot {
  _Snapshot(this.total, this.labels);
  final int total;
  final List<String> labels;

  @override
  String toString() => 'total=$total labels=$labels';
}

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

Widget _harness() => MaterialApp(
      builder: wrapPlatformSemantics,
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text('hello'),
              Switch(value: false, onChanged: null),
            ],
          ),
        ),
      ),
    );

void main() {
  tearDown(() {
    debugSuppressWindowsSemanticsOverride = null;
  });

  testWidgets('suppression ON: semantics tree stays empty of labels',
      (tester) async {
    final handle = tester.ensureSemantics();
    debugSuppressWindowsSemanticsOverride = true;

    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    // Sanity: the content really rendered under the wrap.
    expect(find.text('hello'), findsOneWidget);
    final snap = _snapshot();
    expect(snap.labels, isEmpty,
        reason: 'suppressed tree must not announce anything ($snap)');
    handle.dispose();
  });

  testWidgets('suppression OFF (negative control): labels pass through',
      (tester) async {
    final handle = tester.ensureSemantics();
    debugSuppressWindowsSemanticsOverride = false;

    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(_snapshot().labels, contains('hello'),
        reason: 'without suppression the label must be reachable — this '
            'is the future re-enable path');
    handle.dispose();
  });
}
