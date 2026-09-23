/// Compatibility shim: the throttle moved to `lib/utils/live_seek_throttle.dart`
/// so non-phone scrub surfaces (the linear control-bar slider, the full-screen
/// gesture layers) share the same clock-injected logic.
///
/// The old name stays so existing call sites and tests keep compiling.
library;

import 'package:iris/utils/live_seek_throttle.dart';

export 'package:iris/utils/live_seek_throttle.dart' show LiveSeekThrottle;

typedef PhoneScrubberLiveSeekThrottle = LiveSeekThrottle;
