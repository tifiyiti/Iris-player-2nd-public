import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/windows/desktop_keyboard/store/ab_loop_state.dart';

/// Ephemeral A-B loop holder. Lives outside any widget so the engine's
/// position listener and the overlay chip share one truth.
class AbLoopStore extends Store<AbLoopState> {
  AbLoopStore() : super(const AbLoopState());

  /// Public write path — `set` is store-internal by design.
  void apply(AbLoopState next) => set(next);
}

AbLoopStore useAbLoopStore() => create(() => AbLoopStore());
