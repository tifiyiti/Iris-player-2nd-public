import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/pages/player/control_bar/control_bar_widgets/seek_step_popover.dart';
import 'package:iris/store/use_app_store.dart';

/// Ctrl+↑/↓ opens this popover; while open the global player shortcut handler
/// is gated off (root-navigator modal route), so the popover itself owns ↑/↓
/// (±1s) and Shift+↑/↓ (±10s). These tests drive the real showPopover route.
void main() {
  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async => null);
  });

  setUp(() {
    // Deterministic base for every case (the store is an isolate singleton).
    useAppStore().set(useAppStore().state.copyWith(seekStepSeconds: 5));
  });

  int step() => useAppStore().state.seekStepSeconds;

  Future<void> openPopover(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const StoreScope(
        child: MaterialApp(
          home: Scaffold(
            body: _OpenButton(),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('↑ / ↓ move the base step by 1s', (tester) async {
    await openPopover(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(step(), 6);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(step(), 5);
  });

  testWidgets('Shift+↑ / Shift+↓ move the base step by 10s', (tester) async {
    await openPopover(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(step(), 15);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(step(), 5);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  });

  testWidgets('clamps to [1, 120]', (tester) async {
    useAppStore().set(useAppStore().state.copyWith(seekStepSeconds: 2));
    await openPopover(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(step(), 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(step(), 1);

    useAppStore().set(useAppStore().state.copyWith(seekStepSeconds: 118));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(step(), 120);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(step(), 120);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  });

  testWidgets('renders on a 360-wide surface without overflow', (tester) async {
    await openPopover(tester);
    expect(tester.takeException(), isNull);
  });
}

class _OpenButton extends StatelessWidget {
  const _OpenButton();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: () => showSeekStepPopover(context),
        child: const Text('open'),
      ),
    );
  }
}
