import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/phone/one_handed_scrubber/view/phone_arc_scrubber.dart';
import 'package:iris/features/phone/one_handed_scrubber/view/phone_ring_dial_scrubber.dart';
import 'package:iris/features/phone/one_handed_scrubber/view/phone_snake_scrubber.dart';
import 'package:iris/features/phone/one_handed_scrubber/view/phone_time_lens_scrubber.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/player.dart';
import 'package:provider/provider.dart';

/// Windows AXTree-corruption mitigation (flutter/flutter#182444 family).
///
/// The one-handed scrubbers rebuild on EVERY playback position tick, and
/// their live time texts / badges carry semantics labels — each tick hands
/// the engine's accessibility bridge a mutating node. Once the bridge has
/// been corrupted once, those perpetual updates are what keeps the
/// "Failed to update ui::AXTree" error loop alive. The scrubbers are pure
/// gesture canvases with zero assistive value, so they must contribute NO
/// semantics at all: not on mount, and not across a position tick.
///
/// All variants share ONE testWidgets deliberately (flutter_zustand
/// cross-test store lifecycle: a StoreScope tears its locator streams down
/// when the tree is disposed, so one long-lived tree hosts every mount).
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

Widget _harness(Widget child, Duration position) {
  return StoreScope(
    child: Provider<MediaPlayer>.value(
      value: _player(position),
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 360, height: 360, child: child),
          ),
        ),
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

  final root = RendererBinding.instance.renderViews.first.owner
      ?.semanticsOwner
      ?.rootSemanticsNode;
  if (root != null) visit(root);
  return _Snapshot(total, labels);
}

void main() {
  testWidgets(
      'one-handed scrubbers stay out of the semantics tree across position ticks',
      (tester) async {
    final handle = tester.ensureSemantics();

    // ── Negative control: the counting helper must SEE a real label. ──
    await tester
        .pumpWidget(_harness(const Text('12:34'), const Duration(seconds: 12)));
    await tester.pumpAndSettle();
    expect(_snapshot().labels, contains('12:34'),
        reason: 'counting helper must see real labels');

    final variants = <String, Widget>{
      'snake': PhoneSnakeScrubber(
        showControl: () {},
        color: Colors.white,
        isLeftHanded: false,
      ),
      'arc': PhoneArcScrubber(
        showControl: () {},
        color: Colors.white,
        isLeftHanded: false,
      ),
      'timeLens': PhoneTimeLensScrubber(
        showControl: () {},
        color: Colors.white,
        isLeftHanded: false,
      ),
      'ringDial': PhoneRingDialScrubber(
        showControl: () {},
        color: Colors.white,
        isLeftHanded: false,
      ),
    };

    for (final entry in variants.entries) {
      await tester
          .pumpWidget(_harness(entry.value, const Duration(seconds: 12)));
      await tester.pumpAndSettle();
      final mounted = _snapshot();
      expect(mounted.labels, isEmpty,
          reason: '${entry.key} must not announce anything on mount '
              '(mounted=$mounted)');

      // Simulate a playback position tick: a NEW MediaPlayer instance is
      // pushed through the provider (exactly what player_view does on every
      // position event). The scrubber rebuilds; semantics must not move.
      final beforeTick = mounted;
      await tester
          .pumpWidget(_harness(entry.value, const Duration(seconds: 13)));
      await tester.pumpAndSettle();
      final afterTick = _snapshot();
      expect(afterTick.labels, isEmpty,
          reason: '${entry.key} must not announce anything after a tick');
      expect(afterTick.total, beforeTick.total,
          reason: '${entry.key} position tick must not mutate semantics '
              '(before=$beforeTick after=$afterTick)');
    }

    handle.dispose();
  });
}
