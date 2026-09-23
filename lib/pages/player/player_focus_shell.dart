import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// Gives the player surface its own keyboard-focus node.
///
/// WHY (focus follows the pointer): keyboard ownership for `↑/↓` etc. is
/// decided by `ListKeyboardScope.ownsKey`, which looks at the PRIMARY focus —
/// and the queue list grabs that focus on every pointer-down while the player
/// surface had no focus node at all. One click in the list therefore stranded
/// the focus there forever: clicking the picture changed nothing and `↑/↓`
/// kept moving the queue cursor instead of the volume.
///
/// Contract: clicking anywhere in the player makes THIS node the primary
/// focus, so the list scope no longer resolves and the global player handler
/// takes over again. The shell never processes keys itself and never steals
/// focus from a widget inside the player that legitimately holds it (an
/// in-player control or field takes focus before this ancestor Listener runs,
/// because pointer events dispatch leaf-first).
class PlayerFocusShell extends HookWidget {
  const PlayerFocusShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final focusNode = useMemoized(
      () => FocusNode(debugLabel: 'player-surface'),
      const [],
    );
    useEffect(() => () => focusNode.dispose(), const []);

    return Focus(
      focusNode: focusNode,
      // Not a stop on the Tab tour — it only exists to be focused by a click
      // (and to be the answer to "which surface owns the keys").
      skipTraversal: true,
      // The node conveys nothing to accessibility clients; the player tree is
      // AXTree-sensitive (engine corruption class), so don't grow it.
      includeSemantics: false,
      child: Listener(
        // translucent: claim the WHOLE player rect even where a descendant
        // (letterbox gap, an inert overlay area) does not hit-test — a click
        // anywhere on the picture must hand the keys over. Children are still
        // hit-tested, so nothing inside the player changes behaviour.
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) {
          final primary = FocusManager.instance.primaryFocus;
          // Already ours (the tap landed on an in-player focusable): keep its
          // focus — requestFocus here would yank it back on every click.
          if (primary != null && primary.ancestors.contains(focusNode)) return;
          focusNode.requestFocus();
        },
        child: child,
      ),
    );
  }
}
