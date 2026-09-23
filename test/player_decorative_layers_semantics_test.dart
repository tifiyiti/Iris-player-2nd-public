import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/windows/desktop_keyboard/store/ab_loop_state.dart';
import 'package:iris/features/windows/desktop_keyboard/store/ab_loop_store.dart';
import 'package:iris/features/windows/desktop_keyboard/store/key_sequence_buffer_store.dart';
import 'package:iris/features/windows/desktop_keyboard/view/ab_loop_overlay.dart';
import 'package:iris/features/windows/desktop_keyboard/view/key_sequence_overlay.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/overlays/minimal_progress_overlay.dart';
import 'package:iris/pages/player/control_bar/control_bar_widgets/control_bar_circle_slider.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:provider/provider.dart';

/// Windows crash mitigation (flutter/flutter#103808 family): the engine's
/// accessibility bridge corrupts its AXTree under heavy incremental-update
/// traffic and takes the app down natively (flutter_windows.dll AV). The
/// decorative player layers feed that pipeline every frame while carrying
/// zero information for assistive tech, so each must contribute NO labeled,
/// announceable semantics even in its fully visible state.
///
/// All layers share ONE testWidgets deliberately: a StoreScope tears its
/// locator streams down when the tree is disposed, so mutating global stores
/// from a LATER test after an earlier tree died raises
/// "Cannot add new events after calling close". One tree, sequential mounts.
///
/// VideoView / Audio / GestureOverlay / GestureTipsOverlay get the same
/// ExcludeSemantics wrap but have no standalone harness (native player
/// handles, file IO, cross-store gesture web); their exclusion rides on the
/// identical one-line pattern verified here. A plain Switch acts as the
/// negative control so a broken counting helper can never green-light this.
MediaPlayer _player() {
  return MediaPlayer(
    isInitializing: false,
    isPlaying: false,
    externalSubtitles: const [],
    position: const Duration(seconds: 12),
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

Widget _harness(Widget child) {
  return StoreScope(
    child: Provider<MediaPlayer>.value(
      value: _player(),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Align(child: child)),
      ),
    ),
  );
}

class _Snapshot {
  _Snapshot(this.total, this.labels);
  final int total;
  final List<String> labels;
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

  final root =
      RendererBinding.instance.pipelineOwner.semanticsOwner?.rootSemanticsNode;
  if (root != null) visit(root);
  return _Snapshot(total, labels);
}

void main() {
  testWidgets('decorative player layers stay out of the semantics tree',
      (tester) async {
    final handle = tester.ensureSemantics();

    // ── Negative control: the counting helper must SEE real controls. ──
    await tester.pumpWidget(_harness(Switch(value: false, onChanged: (_) {})));
    await tester.pumpAndSettle();
    expect(_snapshot().total, greaterThan(0),
        reason: 'counting helper must see real interactive controls');

    Future<_Snapshot> pumpLayer(Widget layer) async {
      await tester.pumpWidget(_harness(layer));
      await tester.pumpAndSettle();
      return _snapshot();
    }

    // ── Layer contract: mounting a decorative layer may not introduce ANY
    // new labeled node (labels are what screen readers speak and what the
    // engine serializes on every mutation). Flutter adds at most ONE
    // anonymous full-canvas route-scope node once focusable widgets exist;
    // that scaffold node is static and inert, so it is tolerated. ──
    void expectInert(_Snapshot before, _Snapshot after, String what) {
      expect(after.labels.where((l) => !before.labels.contains(l)), isEmpty,
          reason: '$what must not announce anything');
      expect(after.total, lessThanOrEqualTo(before.total + 1),
          reason: '$what must add at most the anonymous route-scope node');
    }

    // ── `;` waiting chip (armed) ──
    useKeySequenceBufferStore().reset();
    useKeySequenceBufferStore().open();
    final keySeqBase = await pumpLayer(const SizedBox.shrink());
    final keySeqAfter = await pumpLayer(const KeySequenceOverlay());
    expect(find.text('waiting for key…  (F H R X)'), findsOneWidget,
        reason: 'chip must actually render for this assertion to bite');
    expectInert(keySeqBase, keySeqAfter, 'the `;` waiting chip');
    useKeySequenceBufferStore().reset();

    // ── A-B loop chip (looping) ──
    useAbLoopStore()
        .apply(const AbLoopState(enabled: true, pointA: Duration(seconds: 5)));
    final abBase = await pumpLayer(const SizedBox.shrink());
    final abAfter = await pumpLayer(const AbLoopOverlay());
    expectInert(abBase, abAfter, 'the A-B loop chip');
    useAbLoopStore().apply(const AbLoopState());

    // ── Minimal progress overlay (visible) ──
    usePlayerUiStore().updateIsShowControl(false);
    usePlayerUiStore().updateIsShowProgress(true);
    final mpBase = await pumpLayer(const SizedBox.shrink());
    final mpAfter = await pumpLayer(MinimalProgressOverlay(
      title: 'sample',
      file: const FileItem(name: 'a.mp4', uri: 'file:///a.mp4'),
    ));
    expectInert(mpBase, mpAfter, 'the minimal progress overlay');
    usePlayerUiStore().updateIsShowProgress(false);

    // ── Circular progress control ──
    final circleBase = await pumpLayer(const SizedBox.shrink());
    final circleAfter = await pumpLayer(
      const ControlBarCircleSlider(disabled: true),
    );
    expectInert(circleBase, circleAfter, 'the circular progress control');

    handle.dispose();
  });
}
