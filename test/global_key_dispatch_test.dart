import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/hooks/use_global_keyboard.dart';

/// Part E2 regression suite: keyboard shortcuts must keep working regardless
/// of where primary focus lives (the old widget-scoped KeyboardListener went
/// deaf the moment focus moved into the docked playlist panel — a sibling
/// subtree), and the dispatch guards must suppress shortcuts while the user
/// is typing in a text field or a dialog route is on top.
void main() {
  testWidgets('keys reach the handler while focus is in a sibling subtree',
      (tester) async {
    var handled = 0;
    final panelNode = FocusNode();
    await tester.pumpWidget(MaterialApp(
      home: HookBuilder(builder: (context) {
        useGlobalKeyboard((event) {
          if (event is KeyDownEvent) handled++;
        });
        // "Panel" subtree: a focusable that steals primary focus — the old
        // widget-scoped intake stopped receiving events here.
        return Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: Focus(
              focusNode: panelNode,
              child: const SizedBox(width: 50, height: 50),
            ),
          ),
        );
      }),
    ));
    await tester.pump();

    panelNode.requestFocus();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, same(panelNode));

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(handled, 1,
        reason: 'the global intake must see keys even when primary focus '
            'lives outside the registering subtree');
  });

  testWidgets('playerKeysAllowed: false while a TextField has focus',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: TextField(autofocus: true)),
    ));
    await tester.pump();
    final context = tester.element(find.byType(TextField));
    expect(playerKeysAllowed(context), isFalse);
  });

  testWidgets('playerKeysAllowed: false while a dialog route is on top',
      (tester) async {
    late BuildContext captured;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        captured = context;
        return Scaffold(
          body: TextButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const AlertDialog(title: Text('dialog')),
            ),
            child: const Text('open-dialog'),
          ),
        );
      }),
    ));
    await tester.pump();
    expect(playerKeysAllowed(captured), isTrue);

    await tester.tap(find.text('open-dialog'));
    await tester.pumpAndSettle();
    expect(playerKeysAllowed(captured), isFalse,
        reason: 'dialog routes handle their own keys; the player must not '
            'act behind them');
  });

  testWidgets('playerKeysAllowed: true with non-text focus in the same route',
      (tester) async {
    final panelNode = FocusNode();
    late BuildContext captured;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        captured = context;
        return Scaffold(
          body: Focus(
            focusNode: panelNode,
            child: const SizedBox(width: 50, height: 50),
          ),
        );
      }),
    ));
    await tester.pump();
    panelNode.requestFocus();
    await tester.pump();
    expect(playerKeysAllowed(captured), isTrue);
  });
}
