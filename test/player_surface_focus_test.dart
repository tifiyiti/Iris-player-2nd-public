import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/paginated_browser/widgets/list_keyboard_scope.dart';
import 'package:iris/pages/player/player_focus_shell.dart';

KeyEvent _down(LogicalKeyboardKey key) => KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.keyA,
      logicalKey: key,
      timeStamp: Duration.zero,
    );

/// Left half mimics the opt-in queue list (scope + focus node + the
/// pointer-down grab `PaginatedBrowserPage` installs); right half is the
/// player surface under test.
Widget _harness({
  required FocusNode listNode,
  FocusNode? inPlayerNode,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Row(
        children: [
          Expanded(
            child: ListKeyboardScope(
              child: Focus(
                focusNode: listNode,
                child: Listener(
                  onPointerDown: (_) => listNode.requestFocus(),
                  child: const ColoredBox(
                    key: Key('list'),
                    color: Color(0xFFAA0000),
                    // Real height so the tap centre lands inside the box.
                    child: SizedBox(height: 120),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: PlayerFocusShell(
              child: ColoredBox(
                key: const Key('surface'),
                color: const Color(0xFF0000AA),
                child: inPlayerNode == null
                    ? const SizedBox(height: 120)
                    : Focus(
                        focusNode: inPlayerNode,
                        child: const ColoredBox(
                          // ColoredBox, not a bare SizedBox: it hit-tests
                          // itself, so the tap really lands on this control.
                          key: Key('in_player_control'),
                          color: Color(0xFF00FF00),
                          child: SizedBox(width: 40, height: 40),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets(
      'clicking the player surface hands keyboard ownership from the list '
      'to the player (↑/↓ stop being list keys)', (tester) async {
    final listNode = FocusNode(debugLabel: 'list');
    addTearDown(listNode.dispose);

    await tester.pumpWidget(_harness(listNode: listNode));
    await tester.pumpAndSettle();

    // Click the list: it grabs focus and therefore owns the PL keys.
    await tester.tap(find.byKey(const Key('list')));
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, same(listNode));
    expect(
        ListKeyboardScope.ownsKey(_down(LogicalKeyboardKey.arrowDown)), isTrue,
        reason: 'baseline — the focused list owns ↑/↓');

    // Click the picture: focus must follow the pointer, so the list stops
    // owning the arrows and the global handler adjusts the volume again.
    await tester.tap(find.byKey(const Key('surface')));
    await tester.pump();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'player-surface');
    expect(
        ListKeyboardScope.ownsKey(_down(LogicalKeyboardKey.arrowDown)), isFalse,
        reason: 'after clicking the picture ↑/↓ must go back to the player');
    expect(
        ListKeyboardScope.ownsKey(_down(LogicalKeyboardKey.delete)), isFalse);
    expect(ListKeyboardScope.ownsKey(_down(LogicalKeyboardKey.keyD)), isFalse);
  });

  testWidgets(
      'a control inside the player that already holds focus keeps it '
      '(the surface never steals focus back)', (tester) async {
    final listNode = FocusNode(debugLabel: 'list');
    final inPlayerNode = FocusNode(debugLabel: 'in-player');
    addTearDown(listNode.dispose);
    addTearDown(inPlayerNode.dispose);

    await tester
        .pumpWidget(_harness(listNode: listNode, inPlayerNode: inPlayerNode));
    await tester.pumpAndSettle();

    inPlayerNode.requestFocus();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, same(inPlayerNode));

    await tester.tap(find.byKey(const Key('in_player_control')));
    await tester.pump();

    expect(FocusManager.instance.primaryFocus, same(inPlayerNode),
        reason: 'an in-player focusable must keep the focus it just took');
    expect(ListKeyboardScope.ownsKey(_down(LogicalKeyboardKey.arrowDown)),
        isFalse);
  });
}
