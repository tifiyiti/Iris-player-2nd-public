/// Sync-adjustment bounds shared by the keyboard executor and the
/// track-panel controls (phone).
///
/// Pure Dart so both layers stay testable. The canonical step constant is
/// [kSyncStep] in models/player.dart — import from there, never redeclare.
library;

import 'package:iris/models/player.dart' show kSyncStep;

/// PotPlayer-style hard bound: nudging beyond ±1 minute is always a mistake,
/// never a use case.
const double kMaxSyncSeconds = 60.0;

/// Returns the next accumulated delay in seconds after one nudge.
///
/// [direction] is +1 (advance/later) or -1 (delay/earlier).
double nextSyncDelay(double currentSeconds, int direction) {
  assert(direction == 1 || direction == -1);
  final next =
      currentSeconds + direction * (kSyncStep.inMilliseconds / 1000.0);
  return next.clamp(-kMaxSyncSeconds, kMaxSyncSeconds).toDouble();
}
