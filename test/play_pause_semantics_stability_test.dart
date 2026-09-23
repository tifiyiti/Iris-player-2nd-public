import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/control_bar/control_bar_widgets/play_pause_button.dart';
import 'package:provider/provider.dart';

/// AXTree stability: isInitializing flips must not create/destroy semantics
/// nodes. The loading indicator is kept mounted via Offstage so the Windows
/// UIA bridge never sees a reparent/create in the middle of a semantics batch
/// (flutter/flutter #98099/#182444 dangling-node race).

MediaPlayer _player({required bool isInitializing}) {
  return MediaPlayer(
    isInitializing: isInitializing,
    isPlaying: false,
    externalSubtitles: const [],
    position: Duration.zero,
    duration: const Duration(minutes: 10),
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

class _ToggleHost extends StatefulWidget {
  const _ToggleHost();
  @override
  State<_ToggleHost> createState() => _ToggleHostState();
}

class _ToggleHostState extends State<_ToggleHost> {
  bool isInitializing = false;

  @override
  Widget build(BuildContext context) {
    return Provider<MediaPlayer>.value(
      value: _player(isInitializing: isInitializing),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: PlayPauseButton(showControl: () {})),
      ),
    );
  }
}

int _semanticsTotal() {
  var total = 0;
  void visit(SemanticsNode node) {
    total++;
    node.visitChildren((c) {
      visit(c);
      return true;
    });
  }

  final root =
      RendererBinding.instance.pipelineOwner.semanticsOwner?.rootSemanticsNode;
  if (root != null) visit(root);
  return total;
}

void main() {
  testWidgets('PlayPauseButton keeps semantics structure stable across isInitializing',
      (tester) async {
    final handle = tester.ensureSemantics();

    // Single StoreScope for the whole test — avoids "Cannot add new events after
    // calling close" when the scope is torn down between pumpWidgets.
    await tester.pumpWidget(
      StoreScope(child: const _ToggleHost()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final totalNotInitializing = _semanticsTotal();
    expect(totalNotInitializing, greaterThan(0));
    expect(find.byType(IconButton), findsOneWidget);

    // Flip isInitializing inside the same StoreScope / MaterialApp tree.
    final state = tester.state<_ToggleHostState>(find.byType(_ToggleHost));
    state.setState(() => state.isInitializing = true);
    await tester.pump();

    final totalInitializing = _semanticsTotal();
    expect(
      (totalInitializing - totalNotInitializing).abs(),
      lessThanOrEqualTo(1),
      reason:
          'isInitializing must not create/destroy semantics nodes (Offstage stability)',
    );
    expect(find.byType(IconButton), findsOneWidget);

    handle.dispose();
  });
}
