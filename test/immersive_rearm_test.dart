import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/hooks/ui/use_immersive_rearm.dart';
import 'package:iris/utils/platform.dart';

int _harnessBuilds = 0;

class _Harness extends HookWidget {
  const _Harness();

  @override
  Widget build(BuildContext context) {
    _harnessBuilds++;
    useImmersiveRearm();
    return const Scaffold(body: SizedBox.shrink());
  }
}

class _FocusHarness extends HookWidget {
  const _FocusHarness({required this.node});

  final FocusNode node;

  @override
  Widget build(BuildContext context) {
    useImmersiveRearm();
    return Scaffold(body: TextField(focusNode: node));
  }
}

void main() {
  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    debugIsMobilePlatformOverride = true;
  });

  tearDown(() {
    debugIsMobilePlatformOverride = null;
  });

  void mockPlatform(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
  }

  Iterable<MethodCall> immersiveCalls() =>
      calls.where((c) => c.method == 'SystemChrome.setEnabledSystemUIMode');

  testWidgets('re-arms immersion once after the keyboard closes, without rebuilds',
      (tester) async {
    mockPlatform(tester);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
    });

    await tester.pumpWidget(const MaterialApp(home: _Harness()));
    await tester.pump();

    // Keyboard opens.
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    // Keyboard closes.
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump();

    calls.clear();
    _harnessBuilds = 0;
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump();

    final sets = immersiveCalls().toList();
    expect(sets, hasLength(1));
    expect(sets.single.arguments, 'SystemUiMode.immersiveSticky');
    // Metrics changes must not rebuild the widget that hosts the hook.
    expect(_harnessBuilds, 0);
  });

  testWidgets('does not re-arm while an editable still holds focus',
      (tester) async {
    mockPlatform(tester);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
    });

    final node = FocusNode();
    addTearDown(node.dispose);

    await tester.pumpWidget(MaterialApp(home: _FocusHarness(node: node)));
    node.requestFocus();
    await tester.pump();

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump();

    calls.clear();
    await tester.pump(const Duration(milliseconds: 1100));
    expect(immersiveCalls(), isEmpty);
  });

  testWidgets('is a no-op off mobile platforms', (tester) async {
    debugIsMobilePlatformOverride = false;
    mockPlatform(tester);

    await tester.pumpWidget(const MaterialApp(home: _Harness()));
    await tester.pump();

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump();

    calls.clear();
    await tester.pump(const Duration(milliseconds: 1100));
    expect(immersiveCalls(), isEmpty);
  });
}
