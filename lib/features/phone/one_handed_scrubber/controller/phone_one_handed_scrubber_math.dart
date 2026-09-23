import 'dart:math' as math;

/// Converts the compact phone controls into predictable media positions.
///
/// The widgets only provide pointer coordinates. Keeping the duration mapping
/// here makes both experimental controls deterministic and independently testable.
class PhoneArcScrubberMath {
  const PhoneArcScrubberMath._();

  static const double _arcStartRadians = -math.pi / 2;
  static const double _arcSweepRadians = math.pi * 11 / 6;

  static double fractionForAngle(double radians) {
    return (_relativeAngle(radians) / _arcSweepRadians).clamp(0.0, 1.0).toDouble();
  }

  static Duration positionForAngle({
    required Duration duration,
    required double angleRadians,
  }) {
    final double relativeAngle = _relativeAngle(angleRadians)
        .clamp(0.0, _arcSweepRadians)
        .toDouble();
    return _durationForFraction(duration, relativeAngle / _arcSweepRadians);
  }

  static double multiplierFor(PhoneArcScrubPrecision precision) {
    return switch (precision) {
      PhoneArcScrubPrecision.overview => 1.0,
      PhoneArcScrubPrecision.coarse => 1 / 8,
      PhoneArcScrubPrecision.fine => 1 / 32,
    };
  }

  static Duration relativePosition({
    required Duration duration,
    required Duration anchor,
    required double angularDeltaRadians,
    required PhoneArcScrubPrecision precision,
  }) {
    final double multiplier = multiplierFor(precision);
    final double normalizedDelta = _normalizeDelta(angularDeltaRadians);
    final double milliseconds = anchor.inMilliseconds +
        duration.inMilliseconds *
            (normalizedDelta / _arcSweepRadians) *
            multiplier;
    return _clamp(duration, Duration(milliseconds: milliseconds.round()));
  }

  static double _relativeAngle(double angleRadians) {
    double delta = angleRadians - _arcStartRadians;
    delta = delta % (2 * math.pi);
    if (delta < 0) delta += 2 * math.pi;
    if (delta > _arcSweepRadians) {
      const double gap = 2 * math.pi - _arcSweepRadians;
      if (delta > _arcSweepRadians + gap / 2) return 0.0;
    }
    return delta;
  }

  static double _normalizeDelta(double delta) {
    return math.atan2(math.sin(delta), math.cos(delta));
  }

  static Duration _durationForFraction(Duration duration, double fraction) {
    return _clamp(
      duration,
      Duration(milliseconds: (duration.inMilliseconds * fraction).round()),
    );
  }
}

enum PhoneArcScrubPrecision {
  overview,
  coarse,
  fine,
}

/// Tracks one drag on the ring scrubber and keeps the target time continuous
/// across precision-band switches. Merged from dv4-muse-compare but using
/// musespark's seam-corrected math.
class PhoneArcScrubSession {
  PhoneArcScrubSession({required this.duration});

  final Duration duration;

  Duration _target = Duration.zero;
  PhoneArcScrubPrecision _precision = PhoneArcScrubPrecision.overview;
  Duration _relativeAnchor = Duration.zero;
  double _relativeOrigin = 0.0;

  Duration get target => _target;

  void reset({required Duration start}) {
    _target = _clamp(duration, start);
    _precision = PhoneArcScrubPrecision.overview;
    _relativeAnchor = _target;
    _relativeOrigin = 0.0;
  }

  Duration update({
    required double angleRadians,
    required PhoneArcScrubPrecision precision,
  }) {
    final bool enteringRelative = precision != PhoneArcScrubPrecision.overview;
    final bool wasRelative = _precision != PhoneArcScrubPrecision.overview;
    if (precision != _precision) {
      _relativeAnchor = _target;
      _relativeOrigin = angleRadians;
      _precision = precision;
    }
    if (!enteringRelative) {
      _target = PhoneArcScrubberMath.positionForAngle(
        duration: duration,
        angleRadians: angleRadians,
      );
    } else {
      if (!wasRelative && _precision == precision) {
        _relativeAnchor = _target;
        _relativeOrigin = angleRadians;
      }
      _target = PhoneArcScrubberMath.relativePosition(
        duration: duration,
        anchor: _relativeAnchor,
        angularDeltaRadians: angleRadians - _relativeOrigin,
        precision: precision,
      );
    }
    return _target;
  }
}

class PhoneTimeLensScrubberMath {
  const PhoneTimeLensScrubberMath._();

  static const Duration _smallestWindow = Duration(seconds: 30);
  static const List<Duration> _windows = <Duration>[
    Duration(minutes: 30),
    Duration(minutes: 5),
    Duration(seconds: 30),
  ];

  static Duration windowForDepth({
    required Duration duration,
    required double normalizedDepth,
  }) {
    if (normalizedDepth <= 0) return duration;
    if (normalizedDepth <= 1 / 3) return _capToDuration(duration, _windows[0]);
    if (normalizedDepth <= 2 / 3) return _capToDuration(duration, _windows[1]);
    return _capToDuration(duration, _smallestWindow);
  }

  static Duration positionForVerticalDelta({
    required Duration duration,
    required Duration anchor,
    required double verticalDelta,
    required Duration window,
  }) {
    final double offset = window.inMilliseconds * verticalDelta / 2;
    return _clamp(
      duration,
      Duration(milliseconds: (anchor.inMilliseconds + offset).round()),
    );
  }

  static Duration _capToDuration(Duration duration, Duration candidate) {
    return candidate > duration ? duration : candidate;
  }
}

/// Tracks one drag on the time lens and keeps the target continuous when the
/// time window changes.
class PhoneTimeLensScrubSession {
  PhoneTimeLensScrubSession({required this.duration});

  final Duration duration;

  Duration _target = Duration.zero;
  Duration _window = Duration.zero;
  Duration _anchor = Duration.zero;
  double _originY = 0.0;

  Duration get target => _target;
  Duration get window => _window;

  void reset({required Duration start}) {
    _target = _clamp(duration, start);
    _window = duration;
    _anchor = _target;
    _originY = 0.0;
  }

  Duration update({
    required Duration window,
    required double verticalDelta,
  }) {
    if (window != _window) {
      _anchor = _target;
      _originY = verticalDelta;
      _window = window;
    }
    _target = PhoneTimeLensScrubberMath.positionForVerticalDelta(
      duration: duration,
      anchor: _anchor,
      verticalDelta: verticalDelta - _originY,
      window: window,
    );
    return _target;
  }
}

Duration _clamp(Duration duration, Duration candidate) {
  final int milliseconds =
      candidate.inMilliseconds.clamp(0, duration.inMilliseconds).toInt();
  return Duration(milliseconds: milliseconds);
}
