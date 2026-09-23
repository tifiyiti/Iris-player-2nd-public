import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/control_bar/control_bar_slider.dart';
import 'package:iris/pages/player/overlays/minimal_progress_overlay.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:provider/provider.dart';

/// Visibility-gate contract: invisible decorative layers must not subscribe to
/// per-tick MediaPlayer position. Previously MinimalProgressOverlay selected
/// position BEFORE checking isShowProgress/isShowControl, and ControlBarSlider
/// was off-screen via AnimatedPositioned but still subscribed — both caused
/// per-tick rebuilds while invisible (waste + AXTree exposure).

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
  testWidgets('visibility gate: invisible layers stay inert and tick-free',
      (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(_harness(Switch(value: false, onChanged: (_) {})));
    await tester.pumpAndSettle();
    expect(_snapshot().total, greaterThan(0),
        reason: 'counting helper must see real controls');

    Future<_Snapshot> pumpLayer(Widget layer) async {
      await tester.pumpWidget(_harness(layer));
      await tester.pumpAndSettle();
      return _snapshot();
    }

    void expectInert(_Snapshot before, _Snapshot after, String what) {
      expect(after.labels.where((l) => !before.labels.contains(l)), isEmpty,
          reason: '$what must not announce anything');
      expect(after.total, lessThanOrEqualTo(before.total + 1),
          reason: '$what must add at most the anonymous route-scope node');
    }

    // ── MinimalProgressOverlay invisible: isShowProgress=false ──
    usePlayerUiStore().updateIsShowProgress(false);
    usePlayerUiStore().updateIsShowControl(false);
    final mpInvisibleBase = await pumpLayer(const SizedBox.shrink());
    final mpInvisibleAfter = await pumpLayer(MinimalProgressOverlay(
      title: 'sample',
      file: const FileItem(name: 'a.mp4', uri: 'file:///a.mp4'),
    ));
    expect(find.textContaining(' / '), findsNothing,
        reason: 'invisible minimal overlay must not render time text');
    expect(find.byType(Slider), findsNothing,
        reason: 'invisible minimal overlay must not mount slider');
    expectInert(
        mpInvisibleBase, mpInvisibleAfter, 'invisible minimal overlay');

    // ── MinimalProgressOverlay invisible: isShowControl=true (controls shown) ──
    usePlayerUiStore().updateIsShowProgress(true);
    usePlayerUiStore().updateIsShowControl(true);
    final mpCtrlBase = await pumpLayer(const SizedBox.shrink());
    final mpCtrlAfter = await pumpLayer(MinimalProgressOverlay(
      title: 'sample',
      file: const FileItem(name: 'a.mp4', uri: 'file:///a.mp4'),
    ));
    expect(find.textContaining(' / '), findsNothing,
        reason: 'minimal overlay must hide when controls are shown');
    expectInert(mpCtrlBase, mpCtrlAfter, 'minimal overlay with controls shown');
    usePlayerUiStore().updateIsShowProgress(false);
    usePlayerUiStore().updateIsShowControl(false);

    // ── ControlBarSlider invisible: isShowControl=false, disabled=false ──
    usePlayerUiStore().updateIsShowControl(false);
    final sliderInvBase = await pumpLayer(const SizedBox.shrink());
    final sliderInvAfter = await pumpLayer(const ControlBarSlider());
    expect(find.byType(Slider), findsNothing,
        reason: 'off-screen control-bar slider must not mount Slider');
    expectInert(sliderInvBase, sliderInvAfter, 'off-screen control-bar slider');

    // ── ControlBarSlider visible: isShowControl=true, disabled=false ──
    // Contract update (2026-08): the slider exposes ONE static, tick-invariant
    // label so TalkBack traversal keeps it on Android, while every per-tick
    // property stays excluded (see ControlBarSlider.build WHY comment).
    usePlayerUiStore().updateIsShowControl(true);
    final sliderVisBase = await pumpLayer(const SizedBox.shrink());
    final sliderVisAfter = await pumpLayer(const ControlBarSlider());
    expect(find.byType(Slider), findsOneWidget,
        reason: 'visible control-bar slider must render');
    expect(
      sliderVisAfter.labels.where((l) => !sliderVisBase.labels.contains(l)),
      ['Playback position'],
      reason: 'visible slider announces exactly its static label',
    );
    expect(sliderVisAfter.total, lessThanOrEqualTo(sliderVisBase.total + 2),
        reason: 'static label adds one node (+ anonymous route node at most)');

    // ── ControlBarSlider disabled=true (minimal overlay) ignores isShowControl gate ──
    usePlayerUiStore().updateIsShowControl(false);
    final disabledBase = await pumpLayer(const SizedBox.shrink());
    final disabledAfter = await pumpLayer(const ControlBarSlider(disabled: true));
    expect(find.byType(Slider), findsOneWidget,
        reason: 'disabled slider (minimal overlay) must render even when controls hidden');
    expect(
      disabledAfter.labels.where((l) => !disabledBase.labels.contains(l)),
      ['Playback position'],
      reason: 'disabled slider (minimal overlay) keeps the same static label',
    );
    expect(disabledAfter.total, lessThanOrEqualTo(disabledBase.total + 2),
        reason: 'static label adds one node (+ anonymous route node at most)');

    // Cleanup — restore defaults (isShowControl defaults to true)
    usePlayerUiStore().updateIsShowControl(true);
    usePlayerUiStore().updateIsShowProgress(false);

    handle.dispose();
  });
}
