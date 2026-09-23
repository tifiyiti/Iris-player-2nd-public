import 'dart:ui' show KeyEventDeviceType;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/hooks/use_keyboard.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/player.dart';
import 'package:provider/provider.dart';
// Test-only StoreLocator host (see pubspec dev_dependencies comment).
import 'package:zustand/zustand.dart';

/// Requirement #2 (frame playback parity): on the LEGACY keyboard scheme the
/// frame-step keys (`=`, `-`) must keep firing while the key is held down
/// (KeyRepeatEvent → fast frame playback), mirroring the potplayer scheme's
/// repeatable frame actions and the phone float panel's long-press repeat.
/// StoreScope-equivalent that does NOT dispose the global StoreLocator on
/// unmount (mirrors frame_tools_float_panel_test.providerScope).
Widget providerScope(Widget child) {
  return InheritedProvider<StoreLocator>.value(
    value: StoreLocator(),
    startListening: (InheritedContext<StoreLocator?> e, StoreLocator value) {
      final sub = value.changes.listen((_) => e.markNeedsNotifyDependents());
      return sub.cancel;
    },
    lazy: false,
    child: child,
  );
}

void main() {
  final steps = <int>[];
  late MediaPlayer player;
  void Function(KeyEvent)? capturedHandler;

  setUp(() {
    steps.clear();
    capturedHandler = null;
    player = MediaPlayer(
      isInitializing: false,
      isPlaying: false,
      externalSubtitles: const [],
      position: Duration.zero,
      duration: const Duration(minutes: 1),
      buffer: Duration.zero,
      width: 0,
      height: 0,
      saveProgress: () async {},
      play: () async {},
      pause: () async {},
      backward: (_) async {},
      forward: (_) async {},
      stepBackward: () async => steps.add(-1),
      stepForward: () async => steps.add(1),
      seek: (_) async {},
    );
  });

  Future<void> pumpHarness(WidgetTester tester) async {
    await tester.pumpWidget(providerScope(
      Provider<MediaPlayer>.value(
        value: player,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HookBuilder(builder: (context) {
            final handler = useKeyboard(
              showControl: () {},
              showControlForHover: (future) => future,
              showProgress: () {},
            );
            capturedHandler = handler;
            return const SizedBox.shrink();
          }),
        ),
      ),
    ));
    // Deferred l10n delegates load async — settle so the hook captures a
    // resolved handler.
    await tester.pumpAndSettle();
  }

  KeyEvent repeat(LogicalKeyboardKey key) => KeyRepeatEvent(
        deviceType: KeyEventDeviceType.keyboard,
        logicalKey: key,
        physicalKey: PhysicalKeyboardKey.equal,
        timeStamp: Duration.zero,
      );

  KeyEvent down(LogicalKeyboardKey key) => KeyDownEvent(
        deviceType: KeyEventDeviceType.keyboard,
        logicalKey: key,
        physicalKey: PhysicalKeyboardKey.equal,
        timeStamp: Duration.zero,
      );

  testWidgets('legacy: = steps one frame on tap', (tester) async {
    await pumpHarness(tester);
    capturedHandler!(down(LogicalKeyboardKey.equal));
    await tester.pump();
    expect(steps, [1]);
  });

  testWidgets('legacy: = repeats while held (fast frame playback)',
      (tester) async {
    await pumpHarness(tester);
    capturedHandler!(down(LogicalKeyboardKey.equal));
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      capturedHandler!(repeat(LogicalKeyboardKey.equal));
      await tester.pump();
    }
    expect(steps, [1, 1, 1, 1]);
  });

  testWidgets('legacy: - repeats backward while held', (tester) async {
    await pumpHarness(tester);
    capturedHandler!(down(LogicalKeyboardKey.minus));
    await tester.pump();
    for (var i = 0; i < 2; i++) {
      capturedHandler!(repeat(LogicalKeyboardKey.minus));
      await tester.pump();
    }
    expect(steps, [-1, -1, -1]);
  });
}
