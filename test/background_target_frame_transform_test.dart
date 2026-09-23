import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/model/enum/control_target.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/features/background_playback/view/control_target_indicator.dart';
import 'package:provider/provider.dart';
import 'package:zustand/zustand.dart';

Widget _providerScope(Widget child) => InheritedProvider<StoreLocator>.value(
      value: StoreLocator(),
      startListening: (InheritedContext<StoreLocator?> e, StoreLocator value) {
        final sub = value.changes.listen((_) => e.markNeedsNotifyDependents());
        return sub.cancel;
      },
      lazy: false,
      child: child,
    );

const Offset _hideTranslate = Offset(0, 2000);

Widget _harness({required bool frameInsideTransform, required bool hidden}) {
  final bar = Container(height: 60, width: 240, color: Colors.black54);
  final Matrix4 transform = Matrix4.translationValues(
    hidden ? _hideTranslate.dx : 0,
    hidden ? _hideTranslate.dy : 0,
    0,
  );
  final Widget barArea = frameInsideTransform
      ? AnimatedContainer(
          duration: Duration.zero,
          transform: transform,
          child: BackgroundControlTargetIndicator(child: bar),
        )
      : BackgroundControlTargetIndicator(
          child: AnimatedContainer(
            duration: Duration.zero,
            transform: transform,
            child: bar,
          ),
        );
  return _providerScope(
    MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: Align(alignment: Alignment.bottomCenter, child: barArea),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Reads the painted rect straight off the render object: `tester.getRect`
/// cannot be used for a deliberately off-screen widget.
Rect _paintedRect(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  final Offset topLeft = box.localToGlobal(Offset.zero);
  return topLeft & box.size;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ch = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(ch, (call) async => null);

  setUp(() async {
    final bg = useBackgroundPlaybackStore();
    // Must await: load() completes later and its normalizeLoaded() resets the
    // session fields, which would silently wipe the state set here.
    await bg.initialized;
    bg.set(bg.state.copyWith(
      enabled: true,
      // The frame follows the activation: bg must be active for it to draw.
      gateOpen: true,
      controlTarget: ControlTarget.background,
    ));
  });

  tearDown(() => StoreLocator().delete(BackgroundPlaybackStore));

  testWidgets('hidden bar: the frame follows it off-screen', (tester) async {
    await tester.pumpWidget(_harness(frameInsideTransform: true, hidden: true));
    await tester.pump();

    final screen = tester.getRect(find.byType(Scaffold));
    final frame =
        _paintedRect(tester, find.byKey(const ValueKey('bg_control_target_indicator')));
    expect(frame.top, greaterThanOrEqualTo(screen.bottom),
        reason: 'a hidden bar must take its frame with it');
  });

  testWidgets('this test catches the old (frame-outside) wiring',
      (tester) async {
    await tester.pumpWidget(_harness(frameInsideTransform: false, hidden: true));
    await tester.pump();

    final screen = tester.getRect(find.byType(Scaffold));
    final frame =
        _paintedRect(tester, find.byKey(const ValueKey('bg_control_target_indicator')));
    expect(frame.top, lessThan(screen.bottom),
        reason: 'sanity: the old wiring really did strand the frame on screen');
  });

  testWidgets('shown bar: the frame still hugs it', (tester) async {
    await tester.pumpWidget(_harness(frameInsideTransform: true, hidden: false));
    await tester.pump();

    final screen = tester.getRect(find.byType(Scaffold));
    final frame =
        _paintedRect(tester, find.byKey(const ValueKey('bg_control_target_indicator')));
    expect(frame.width, lessThan(screen.width));
    expect(frame.bottom, closeTo(screen.bottom, 1));
  });
}
