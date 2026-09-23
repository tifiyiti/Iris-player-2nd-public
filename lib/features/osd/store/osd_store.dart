import 'dart:async';

import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/osd/model/osd_entry.dart';

/// Ephemeral OSD state — mirrors `KeySequenceBufferStore` lifecycle but
/// driven by keyboard executor instead of the sequence buffer.
///
/// The timer is owned by the STORE (not the widget) so hide timing survives
/// rebuilds and a second `show` while already visible simply resets the clock
/// (no dangling timers, PotPlayer-style de-duplication).
class OsdStore extends Store<OsdEntry?> {
  OsdStore() : super(null);

  Timer? _timer;

  /// Shows [entry] for [duration] (default from `AppState.osdDurationMs` via
  /// the executor). Cancels any pending hide timer so rapid repeats
  /// (volume hold, seek hold) keep the OSD alive and always reflect the
  /// latest value.
  void show(OsdEntry entry, {Duration duration = const Duration(milliseconds: 2000)}) {
    _timer?.cancel();
    set(entry);
    _timer = Timer(duration, () => set(null));
  }

  void hide() {
    _timer?.cancel();
    set(null);
  }

  @override
  Future<void> dispose() async {
    _timer?.cancel();
    await super.dispose();
  }
}

final _osdStore = create(() => OsdStore());

OsdStore useOsdStore() => _osdStore;
