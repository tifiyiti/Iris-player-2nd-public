import 'package:flutter/material.dart';

/// The ONE widget allowed to consume the software-keyboard inset.
///
/// Reading `MediaQuery.viewInsetsOf` rebuilds the reading widget on EVERY
/// keyboard animation frame. Isolating that read in this leaf keeps the
/// caller's subtree (a form, a list) out of those rebuilds: keyboard frames
/// merely repad the already-built child. This is the pattern proven by
/// `vm_rule_editor_v2.dart` after the V1 stall (a form that read viewInsets
/// itself rebuilt every field on every frame).
///
/// Use it exactly once per popup shell. In a `Dialog` it is inert (the `Dialog`
/// removes view insets from its child and pads itself); in a bottom sheet it is
/// the keyboard-avoidance mechanism.
class KeyboardInsetPadder extends StatelessWidget {
  const KeyboardInsetPadder({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: child,
    );
  }
}
