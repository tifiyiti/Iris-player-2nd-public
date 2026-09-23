import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/utils/platform.dart';
import 'package:iris/widgets/adaptive/ime_focus_reshow.dart';

class _Harness extends HookWidget {
  const _Harness({required this.a, required this.b, required this.plain});

  final FocusNode a;
  final FocusNode b;
  final FocusNode plain;

  @override
  Widget build(BuildContext context) {
    useImeReshowOnFocusChange();
    return Scaffold(
      body: Column(
        children: [
          TextField(focusNode: a),
          TextField(focusNode: b),
          Focus(focusNode: plain, child: const SizedBox(height: 20)),
        ],
      ),
    );
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

  void mockTextInput(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.textInput,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.textInput, null));
  }

  Iterable<MethodCall> showCalls() =>
      calls.where((c) => c.method == 'TextInput.show');

  Future<(FocusNode, FocusNode, FocusNode)> pumpHarness(
      WidgetTester tester) async {
    final a = FocusNode();
    final b = FocusNode();
    final plain = FocusNode();
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    addTearDown(plain.dispose);
    await tester.pumpWidget(
      MaterialApp(home: _Harness(a: a, b: b, plain: plain)),
    );
    await tester.pump();
    return (a, b, plain);
  }

  testWidgets('replays the IME show on every field-to-field focus move',
      (tester) async {
    mockTextInput(tester);
    final (a, b, _) = await pumpHarness(tester);

    a.requestFocus();
    await tester.pump();
    calls.clear();
    await tester.pump(const Duration(milliseconds: 500));
    final normalToPassword = showCalls().length;

    // The reverse direction (what previously still needed a second tap):
    b.requestFocus();
    await tester.pump();
    calls.clear();
    await tester.pump(const Duration(milliseconds: 500));
    final passwordToNormal = showCalls().length;

    expect(normalToPassword, greaterThanOrEqualTo(2));
    expect(passwordToNormal, greaterThanOrEqualTo(2));
  });

  testWidgets('does not replay when focus leaves the text fields',
      (tester) async {
    mockTextInput(tester);
    final (a, _, plain) = await pumpHarness(tester);

    a.requestFocus();
    await tester.pump();
    plain.requestFocus();
    await tester.pump();

    calls.clear();
    await tester.pump(const Duration(milliseconds: 500));
    expect(showCalls(), isEmpty);
  });

  testWidgets('is a no-op off mobile platforms', (tester) async {
    debugIsMobilePlatformOverride = false;
    mockTextInput(tester);
    final (a, _, _) = await pumpHarness(tester);

    a.requestFocus();
    await tester.pump();
    calls.clear();
    await tester.pump(const Duration(milliseconds: 500));

    // Only the framework's own single show for the newly focused field.
    expect(showCalls().length, lessThanOrEqualTo(1));
  });
}
