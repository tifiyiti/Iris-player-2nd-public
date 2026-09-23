import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/utils/platform.dart';

/// Re-applies immersive mode once the soft keyboard closes.
///
/// Android force-shows the system bars while the IME is up and, per the
/// platform contract, will not restore the app's previous UI visibility for
/// about one second after the keyboard closes (flutter/flutter #89780).
/// Without this the player is left non-immersive after any text entry. This
/// hook does ZERO per-frame work beyond comparing two doubles on metrics
/// changes and never rebuilds a widget; the platform call happens at most once
/// per keyboard dismissal.
void useImmersiveRearm() {
  final context = useContext();
  // Identity-only dependency (_ViewScope): never rebuilds on inset changes.
  final view = View.maybeOf(context);
  final timer = useRef<Timer?>(null);

  useEffect(() {
    if (!isMobilePlatform || view == null) return null;

    double keyboardInset() {
      final dpr = view.devicePixelRatio;
      final bottom = view.viewInsets.bottom;
      return dpr == 0 ? bottom : bottom / dpr;
    }

    double lastInset = keyboardInset();

    void arm() {
      timer.value?.cancel();
      // The OS locks UI-visibility changes for ~1s after the keyboard closes.
      timer.value = Timer(const Duration(milliseconds: 1000), () {
        timer.value = null;
        final focusContext = FocusManager.instance.primaryFocus?.context;
        if (focusContext != null &&
            focusContext.findAncestorStateOfType<EditableTextState>() != null) {
          return;
        }
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      });
    }

    final observer = _ImmersiveRearmObserver(
      onMetrics: () {
        final now = keyboardInset();
        final prev = lastInset;
        lastInset = now;
        if (prev > 0 && now == 0) {
          arm();
        } else if (now > 0) {
          // Keyboard re-opened before the re-arm fired: drop it.
          timer.value?.cancel();
          timer.value = null;
        }
      },
      onResumed: () {
        lastInset = keyboardInset();
        if (lastInset == 0) arm();
      },
    );

    WidgetsBinding.instance.addObserver(observer);
    return () {
      WidgetsBinding.instance.removeObserver(observer);
      timer.value?.cancel();
      timer.value = null;
    };
  }, const []);
}

class _ImmersiveRearmObserver extends WidgetsBindingObserver {
  _ImmersiveRearmObserver({required this.onMetrics, required this.onResumed});

  final VoidCallback onMetrics;
  final VoidCallback onResumed;

  @override
  void didChangeMetrics() => onMetrics();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResumed();
  }
}
