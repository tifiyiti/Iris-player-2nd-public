import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// Creates a PER-MOUNT [GlobalKey] and publishes it to [notifier] while the
/// widget is alive.
///
/// WHY (flutter/flutter #177693 / #188500, the #182444 family): a widget whose
/// box is looked up by another layer (style popovers, keyboard shortcuts) needs
/// a key that the lookup can resolve — but that key must NOT be a shared object
/// reused by every mount. A shared key lets a NEW element re-take the OLD,
/// deactivated one (`Element._retakeInactiveElement`, framework.dart:4481 — it
/// even steals a still-active child). Re-activating the old element re-activates
/// every `OverlayPortal` inside it (Tooltips, a Slider's value indicator), and
/// `_OverlayPortalElement.activate` grafts the deferred child into the root
/// overlay BEFORE the new parent is attached — so the mutation lands with no
/// actively-laying-out ancestor: `_RenderLayoutBuilder was mutated in
/// performLayout`, then a poisoned element tree (`Lost connection to device`,
/// bogus `RenderFlex overflowed by 97890 pixels`).
///
/// A per-mount key can never be re-taken, so the subtree always mounts fresh
/// (mounting during layout is legal and is what happens on every normal build).
/// Readers keep the same semantics as before: a fresh lookup at use time via
/// `notifier.value?.currentContext`.
GlobalKey<T> usePublishedGlobalKey<T extends State<StatefulWidget>>(
  ValueNotifier<GlobalKey<T>?> notifier,
) {
  final GlobalKey<T> key = useMemoized(GlobalKey<T>.new, const <Object?>[]);
  useEffect(() {
    notifier.value = key;
    return () {
      // Retract on unmount so no reader ever resolves a dead box and a later
      // mount publishes its own key.
      if (identical(notifier.value, key)) {
        notifier.value = null;
      }
    };
  }, const <Object?>[]);
  return key;
}
