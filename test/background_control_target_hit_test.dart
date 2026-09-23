import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/model/enum/control_target.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/features/background_playback/view/control_target_indicator.dart';
import 'package:provider/provider.dart';
import 'package:zustand/zustand.dart';

/// The 副音 control-target frame must mark the CONTROL BAR only — never the
/// whole screen, and never in a way that swallows taps meant for the video
/// surface (which is what summons the control bar in the first place).
Widget _providerScope(Widget child) {
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
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  tearDown(() => StoreLocator().delete(BackgroundPlaybackStore));

  Future<void> armBackgroundTarget() async {
    final bg = useBackgroundPlaybackStore();
    await bg.initialized;
    bg.set(bg.state.copyWith(
      enabled: true,
      gateOpen: true,
      controlTarget: ControlTarget.background,
    ));
  }

  /// Mirrors ControlsOverlay's wiring: the indicator wraps the BAR, inside a
  /// full-screen Positioned.fill/Align.
  Widget barStack({required bool wrapBar}) {
    final bar = SizedBox(
      height: 60,
      width: 240,
      child: ColoredBox(color: Colors.black54),
    );
    return Stack(
      children: [
        Positioned.fill(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: wrapBar
                ? BackgroundControlTargetIndicator(child: bar)
                : bar,
          ),
        ),
      ],
    );
  }

  testWidgets('the frame does not swallow taps on the surface underneath',
      (tester) async {
    await armBackgroundTarget();
    var surfaceTapped = false;

    await tester.pumpWidget(_providerScope(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => surfaceTapped = true,
                child: const SizedBox.expand(),
              ),
              barStack(wrapBar: true),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('bg_control_target_indicator')),
      findsOneWidget,
    );
    // Tap far from the bar — must reach the surface below.
    await tester.tapAt(const Offset(100, 100));
    await tester.pump();
    expect(surfaceTapped, isTrue,
        reason: 'the target frame must never absorb surface taps');
  });

  testWidgets('a closed gate never draws the bg frame (bg not active)',
      (tester) async {
    final bg = useBackgroundPlaybackStore();
    await bg.initialized;
    // A stale target flag must not route anything to bg once deactivated.
    bg.set(bg.state.copyWith(
      enabled: true,
      gateOpen: false,
      controlTarget: ControlTarget.background,
    ));

    await tester.pumpWidget(_providerScope(
      MaterialApp(home: Scaffold(body: barStack(wrapBar: true))),
    ));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('bg_control_target_indicator')),
      findsNothing,
      reason: 'the frame must follow the activation, not a stale flag',
    );
  });

  testWidgets('the frame hugs the bar, not the whole screen', (tester) async {
    await armBackgroundTarget();

    await tester.pumpWidget(_providerScope(
      MaterialApp(home: Scaffold(body: barStack(wrapBar: true))),
    ));
    await tester.pump();

    final frame = tester.getRect(
      find.byKey(const ValueKey('bg_control_target_indicator')),
    );
    final screen = tester.getRect(find.byType(Scaffold));
    expect(frame.width, lessThan(screen.width),
        reason: 'the frame must not span the screen width');
    expect(frame.height, lessThan(screen.height),
        reason: 'the frame must not span the screen height');
    // It should just outline the 240x60 bar.
    expect(frame.width, lessThanOrEqualTo(248));
    expect(frame.height, lessThanOrEqualTo(68));
  });
}
