import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/view/widgets/progress_chip.dart';

/// Windows AXTree-corruption mitigation (flutter/flutter#182444 family).
///
/// Progress chips sit inside paged popups over the playing video and tick
/// every second while a live progress record streams in. Their percent text
/// is decorative (redundant with the row title and the player itself), yet
/// each update hands the engine's accessibility bridge a mutating node —
/// exactly the traffic that keeps a corrupted AXTree error loop alive. The
/// chip must therefore contribute NO labeled semantics.
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
  testWidgets('progress chip stays out of the semantics tree', (tester) async {
    final handle = tester.ensureSemantics();

    // Negative control: the counting helper must SEE a real label.
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: Text('42 %'))),
    ));
    await tester.pumpAndSettle();
    expect(_snapshot().labels, contains('42 %'),
        reason: 'counting helper must see real labels');

    // The chip renders its percent text...
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(child: ProgressChip(positionMs: 42000, durationMs: 100000)),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('42 %'), findsOneWidget,
        reason: 'chip must actually render for this assertion to bite');

    // ...but contributes no labeled semantics node.
    expect(_snapshot().labels, isEmpty,
        reason: 'progress chip is decorative and must not announce');

    handle.dispose();
  });
}
