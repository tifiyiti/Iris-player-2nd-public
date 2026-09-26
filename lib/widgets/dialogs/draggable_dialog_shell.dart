import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// Hands a descendant drag handle the callbacks it needs to move the dialog.
///
/// The handle must be a DESCENDANT rather than the whole card: a card-wide pan
/// recognizer competes with the sliders and wheel scroll views inside for the
/// gesture arena, which is why the side-panel editor also drags by its header
/// only.
class DraggableDialogScope extends InheritedWidget {
  const DraggableDialogScope({
    super.key,
    required this.onDragUpdate,
    required this.onDragEnd,
    required super.child,
  });

  /// Pixels the pointer moved since the previous frame.
  final ValueChanged<Offset> onDragUpdate;

  /// Fired once when the gesture finishes, so the caller can persist.
  final VoidCallback onDragEnd;

  static DraggableDialogScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DraggableDialogScope>();

  @override
  bool updateShouldNotify(DraggableDialogScope oldWidget) => false;
}

/// Modal shell that lets the user park [child] anywhere on screen.
///
/// The position is a FRACTION (0..1) of the travel available to the card, 0.5
/// being centred. Fractions rather than pixels because a pixel offset drifts
/// the moment the viewport changes — a card parked in a corner keeps its old
/// offset and stops being corner-anchored. Fraction space also means the card
/// cannot leave the safe area by construction, so there is no clamping pass to
/// get wrong.
///
/// Performance: a drag moves the card with a paint-time `Transform.translate`
/// and the card is handed to [ValueListenableBuilder.child], so neither the
/// card nor its subtree is laid out or rebuilt while the finger moves. That is
/// the whole point here — the card holds `ListWheelScrollView`s and a `Slider`,
/// and rebuilding those per frame is exactly the phone jank to avoid.
class DraggableDialogShell extends HookWidget {
  const DraggableDialogShell({
    super.key,
    required this.initialFraction,
    required this.onCommit,
    required this.dismissible,
    required this.child,
  });

  /// Remembered spot, 0..1 of the available travel; `Offset(0.5, 0.5)` centres.
  final Offset initialFraction;

  /// Called once per gesture, with the fraction the card came to rest at.
  final ValueChanged<Offset> onCommit;

  /// Whether tapping the scrim dismisses the route.
  ///
  /// The shell paints its OWN scrim instead of letting the route's barrier
  /// handle it, so this flag is what the tap layer consults. A form holding
  /// unsaved input passes false and must survive a stray click — the route's
  /// `barrierDismissible` alone cannot express that here.
  final bool dismissible;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Size screen = MediaQuery.sizeOf(context);
    final EdgeInsets safe = MediaQuery.paddingOf(context);
    final ValueNotifier<Offset> fraction = useState<Offset>(initialFraction);
    final ValueNotifier<Size> cardSize = useState<Size>(Size.zero);
    final GlobalKey boxKey = useMemoized<GlobalKey>(() => GlobalKey());

    // Sizes exist only after layout, so the first frame measures the card and
    // repaints against it. Re-runs on every viewport change for the same
    // reason: a fraction is only meaningful relative to the space it divides.
    useEffect(
      () {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final RenderObject? box = boxKey.currentContext?.findRenderObject();
          if (box is RenderBox && box.hasSize && box.size != cardSize.value) {
            cardSize.value = box.size;
          }
        });
        return null;
      },
      <Object?>[screen],
    );

    /// Travel the card has inside the safe area (never negative).
    Offset freeSpace() => Offset(
          math.max(0.0, screen.width - safe.horizontal - cardSize.value.width),
          math.max(0.0, screen.height - safe.vertical - cardSize.value.height),
        );

    /// Pixels from the centred resting position for [f].
    Offset shiftOf(Offset f) {
      final Offset space = freeSpace();
      return Offset((f.dx - 0.5) * space.dx, (f.dy - 0.5) * space.dy);
    }

    void dragBy(Offset delta) {
      final Offset space = freeSpace();
      final Offset current = fraction.value;
      fraction.value = Offset(
        space.dx <= 0
            ? 0.5
            : (current.dx + delta.dx / space.dx).clamp(0.0, 1.0).toDouble(),
        space.dy <= 0
            ? 0.5
            : (current.dy + delta.dy / space.dy).clamp(0.0, 1.0).toDouble(),
      );
    }

    return DraggableDialogScope(
      onDragUpdate: dragBy,
      onDragEnd: () => onCommit(fraction.value),
      child: Stack(
        children: <Widget>[
          // The barrier sits OUTSIDE the listenable builder, so a drag frame
          // never rebuilds it.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              // Swallowed when the form opts out of dismissal: a non-dismissible
              // scrim must still absorb the tap (so it does not reach whatever
              // is behind the route) but must NOT pop the route.
              onTap: dismissible ? () => Navigator.of(context).pop() : null,
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
          Positioned.fill(
            child: SafeArea(
              child: Center(
                child: ValueListenableBuilder<Offset>(
                  valueListenable: fraction,
                  // `child` is passed through, never rebuilt: the card and its
                  // wheels keep their elements for the whole drag.
                  child: KeyedSubtree(key: boxKey, child: child),
                  builder: (BuildContext context, Offset f, Widget? child) =>
                      Transform.translate(offset: shiftOf(f), child: child),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
