import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/control_bar/control_bar_slider.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:provider/provider.dart';

/// AXTree stability × Android a11y (flutter/flutter#182444 aftermath).
///
/// The seek slider's value and flanking time texts churn every playback
/// tick, so the ticking subtree stays EXCLUDED from semantics. But a fully
/// silent slider also drops the slider from TalkBack traversal entirely on
/// Android (which has no Windows-style AXTree bug and keeps its a11y). The
/// contract: the slider row exposes exactly ONE static semantics node —
/// a stable label with no live value — so traversal announces it without
/// any per-tick updates feeding the bridge.
MediaPlayer _player(Duration position) {
  return MediaPlayer(
    isInitializing: false,
    isPlaying: false,
    externalSubtitles: const [],
    position: position,
    duration: const Duration(hours: 1),
    buffer: Duration.zero,
    width: 16,
    height: 9,
    saveProgress: () async {},
    play: () async {},
    pause: () async {},
    backward: (_) async {},
    forward: (_) async {},
    stepBackward: () async {},
    stepForward: () async {},
    seek: (_) async {},
  );
}

Widget _harness(Duration position) {
  return StoreScope(
    child: Provider<MediaPlayer>.value(
      value: _player(position),
      child: const MaterialApp(
        home: Scaffold(body: Center(child: ControlBarSlider())),
      ),
    ),
  );
}

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

void main() {
  testWidgets('seek slider exposes one static, tick-invariant label',
      (tester) async {
    final handle = tester.ensureSemantics();

    // The slider early-returns while the control bar is hidden; make it
    // visible so the assertion can bite.
    usePlayerUiStore().updateIsShowControl(true);
    await tester.pumpWidget(_harness(const Duration(seconds: 12)));
    await tester.pumpAndSettle();
    final mounted = _snapshot();

    expect(mounted.labels.length, 1,
        reason: 'exactly one static label must exist ($mounted)');
    expect(find.byType(Slider), findsOneWidget,
        reason: 'slider must actually render for this assertion to bite');

    // Position tick: a NEW MediaPlayer instance flows through the provider
    // (what player_view does on every position event). The label must not
    // move and no extra labeled node may appear — zero churn.
    await tester.pumpWidget(_harness(const Duration(seconds: 13)));
    await tester.pumpAndSettle();
    final afterTick = _snapshot();
    expect(afterTick.labels, mounted.labels,
        reason: 'position tick must not mutate semantics '
            '(before=$mounted after=$afterTick)');

    handle.dispose();
  });
}
