import 'package:media_kit/media_kit.dart';

/// media_kit (mpv) seek / cache tuning.
///
/// media_kit overrides several mpv defaults with values that make precise
/// seeking visibly slower (see
/// `media_kit/lib/src/player/native/player/real.dart`):
///
///  * `hr-seek=yes` + `hr-seek-framedrop=no` — a precise seek DECODES AND
///    DISPLAYS every frame between the previous keyframe and the target. mpv's
///    own default is `hr-seek-framedrop=yes` (drop those frames), so this
///    single override is what turns a keyframe-distant seek into a visible
///    "catch-up"/lag on fast-forward / rewind.
///  * `demuxer-max-bytes` / `demuxer-max-back-bytes` pinned to
///    `PlayerConfiguration.bufferSize` (32MiB) — below mpv's upstream
///    150MiB/75MiB, so rewinding high-bitrate media re-demuxes constantly.
///
/// Re-assert the values after `Player` construction so both the frame drop and
/// the cache sizing are under IRIS's control (and user-tunable via the
/// `playback.videoCachePreset` meta-setting).
Future<void> applyMpvSeekTuning(
  NativePlayer player, {
  required int cacheMaxBytes,
  required int cacheBackBytes,
}) async {
  // mpv requires the backward cache to be <= the forward one.
  final int back =
      cacheBackBytes > cacheMaxBytes ? cacheMaxBytes : cacheBackBytes;
  try {
    await player.setProperty('hr-seek', 'yes');
    await player.setProperty('hr-seek-framedrop', 'yes');
    await player.setProperty('demuxer-max-bytes', '$cacheMaxBytes');
    await player.setProperty('demuxer-max-back-bytes', '$back');
  } catch (_) {
    // A backend without these properties keeps mpv's own defaults; seeking
    // must never break because tuning failed.
  }
}

/// Base position (ms) a RELATIVE step must add its delta to, while no step
/// accumulation is in flight — see [StepIntent], which layers the step
/// intent on top of this fallback.
///
/// While a user seek is still in flight the reported position lags the intent
/// (mpv is still decoding toward the target), so chaining `+N` onto it drifts
/// backwards — a held arrow key would then advance by less than one step per
/// press, or by nothing at all. When an intent target is armed, accumulate onto
/// that so every press lands exactly one step further.
int resolveRelativeBaseMs({
  required int reportedMs,
  required int? pendingIntentMs,
}) =>
    pendingIntentMs ?? reportedMs;

/// Lock-independent accumulator for relative STEP seeks (← / → fast-forward).
///
/// The position-lock intent (`resolveRelativeBaseMs`) cannot anchor a step
/// burst on its own: the lock unlocks as soon as one sample lands within its
/// ±2s tolerance (`isLandingAt`), and there are further fail-open
/// `unlock()` paths (open error, lock timeout). Once unlocked the step base
/// falls back to the REPORTED position — which does not advance during a
/// burst, because `noteStepSeek` switches the engine to `hr-seek=no` and
/// media_kit's `seek` command is a plain `absolute` (inexact) seek: mpv snaps
/// back to the previous keyframe. On a 60fps file with `keyint=250` (GOP
/// ≈ 4.17s) a 4s step stays inside the SAME GOP, so every press recomputes
/// the same target — N presses advance nothing and the burst settle lands on
/// that same plateau.
///
/// Recording the last requested target here keeps the accumulation alive for
/// the whole burst, independent of the lock's phase and of what the engine
/// reports. Callers reset it when the base axis changes (absolute seek,
/// media change) so the next step re-anchors on the fresh position.
///
/// Pure clock-free logic: unit-testable without a player.
class StepIntent {
  int? _lastMs;

  /// The most recently requested step target, in the caller's coordinate axis
  /// (segment-local while a VM session is active), or null when none/reset.
  int? get lastMs => _lastMs;

  /// Records the target a step seek is heading to.
  void note(int targetMs) => _lastMs = targetMs;

  /// Drops the accumulation (absolute seek / media change / backend reset).
  void reset() => _lastMs = null;

  /// Base position the next relative step must add its delta to:
  /// step intent → position-lock intent → reported position. The last two
  /// are the [resolveRelativeBaseMs] fallback chain, which only covers a
  /// seek that is still IN FLIGHT — hence the step intent above it.
  int baseFor({required int reportedMs, required int? lockIntentMs}) =>
      _lastMs ??
      resolveRelativeBaseMs(reportedMs: reportedMs, pendingIntentMs: lockIntentMs);
}

/// Trailing window that collapses a user-seek progress-write burst into the
/// leading target (written immediately) plus one trailing write.
const Duration kUserSeekWriteDebounce = Duration(milliseconds: 350);

/// Idle window that ends a rapid step burst (a press arriving inside it keeps
/// the burst alive).
const Duration kStepBurstWindow = Duration(milliseconds: 400);

/// Minimum spacing between ENGINE seeks for a step burst.
///
/// mpv presents nothing while a seek is in flight, so firing one seek per
/// keyboard repeat (~30/s) means no seek ever finishes and the picture stays on
/// the old frame until the repeats stop — the "frozen, then one big jump"
/// symptom. Spacing the engine seeks out (the same ~120ms contract the scrub
/// surfaces already use) lets each one land and paint a frame, so a press shows
/// a frame and a hold advances step by step. The intent target still
/// accumulates on every press; a throttled target is landed by the burst's
/// idle settle.
const Duration kStepSeekMinInterval = Duration(milliseconds: 120);

/// Rapid-step burst detector for keyboard / double-tap fast-forward & rewind.
///
/// A single deliberate press stays on the default (exact) seek path. Once a
/// SECOND step lands within [window] the burst is "rapid" and the engine is
/// switched to cheap keyframe seeks — which mpv lands (and paints) immediately,
/// so every press shows a frame and holding advances continuously. The caller
/// restores exact seeking and lands the precise target when the burst goes
/// idle.
///
/// Pure clock-injected logic: unit-testable without a player.
class StepBurst {
  StepBurst({this.window = kStepBurstWindow});

  final Duration window;

  DateTime? _lastAt;
  bool _rapid = false;

  bool get isRapid => _rapid;

  /// Records a step at [now]; returns true once the burst counts as rapid.
  bool note(DateTime now) {
    final DateTime? last = _lastAt;
    _lastAt = now;
    if (last != null && now.difference(last) < window) _rapid = true;
    return _rapid;
  }

  void reset() {
    _lastAt = null;
    _rapid = false;
  }
}

/// Trailing-edge coalescer: keeps only the newest value of a burst.
///
/// Used for user-seek PROGRESS WRITES only — during a held-key / drag burst just
/// the first target (leading edge, persisted immediately for kill-safety) and
/// the last one (trailing flush) reach the UI-isolate Drift.
///
/// Deliberately NOT applied to the seeks themselves: collapsing engine seeks
/// would make a held arrow key stand still and then jump once, instead of
/// advancing frame by frame.
class TrailingCoalescer<T> {
  T? _pending;

  bool get hasPending => _pending != null;

  void record(T value) => _pending = value;

  /// Takes the newest pending value and clears it. Null when nothing pending.
  T? flush() {
    final T? p = _pending;
    _pending = null;
    return p;
  }
}
