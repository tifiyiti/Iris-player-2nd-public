import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart' show immutable;

/// Where the shared keyboard form sits and how wide it is.
///
/// Both axes are FRACTIONS, never pixels: a pixel offset or width drifts the
/// moment the window is resized or the device rotates, so a form parked in a
/// corner would keep a stale offset and stop being corner-anchored. A
/// [widthFraction] of null means "no stored preference" — the form sizes itself
/// to the viewport.
///
/// Persisted as one `form.geometry` AUX row; the two axes share a value because
/// a resize and a move are two views of the same box.
@immutable
class KeyboardFormGeometry {
  const KeyboardFormGeometry({
    this.offset = const Offset(0.5, 0.5),
    this.widthFraction,
  });

  /// Resting place, 0..1 of the travel inside the safe area; 0.5 is centred.
  final Offset offset;

  /// Width as a share of the available width; null = size to the viewport.
  final double? widthFraction;

  /// The centred, auto-width default a fresh install (or a corrupt row) gets.
  static const KeyboardFormGeometry kDefault = KeyboardFormGeometry();

  /// Fractions are clamped into [0,1] so a stored value can never park the
  /// form outside its travel.
  ///
  /// A non-finite WIDTH degrades to null ("auto"), matching [sanitizeWidth]
  /// and [resolveKeyboardFormWidth]. It used to fall through [clampFraction] to
  /// 0.5, so a corrupt row produced a 50%-wide card on the write path while
  /// the same value read back as auto — the two paths disagreed about what one
  /// bad number meant.
  factory KeyboardFormGeometry.clamped({
    required Offset offset,
    double? widthFraction,
  }) =>
      KeyboardFormGeometry(
        offset: Offset(clampFraction(offset.dx), clampFraction(offset.dy)),
        widthFraction: sanitizeWidth(widthFraction),
      );

  /// A stored fraction, or null for anything unusable (not a number, NaN, or
  /// infinity). Null means "auto" on both the read and the write path.
  static double? sanitizeWidth(Object? raw) {
    if (raw is! num) return null;
    final double value = raw.toDouble();
    if (!value.isFinite) return null;
    return clampFraction(value);
  }

  static double clampFraction(double value) =>
      value.isFinite ? value.clamp(0.0, 1.0).toDouble() : 0.5;

  /// `dx,dy[,widthFraction]` — the same bare "x,y" shape the speed picker card
  /// already round-trips. Never throws: anything unparseable yields [kDefault],
  /// because a corrupt geometry must not strand the form off-screen.
  static KeyboardFormGeometry parse(String? raw) {
    if (raw == null) return kDefault;
    final List<String> parts = raw.split(',');
    if (parts.length < 2 || parts.length > 3) return kDefault;
    final double? dx = double.tryParse(parts[0].trim());
    final double? dy = double.tryParse(parts[1].trim());
    if (dx == null || dy == null) return kDefault;
    return KeyboardFormGeometry.clamped(
      offset: Offset(dx, dy),
      widthFraction: parts.length == 3 ? sanitizeWidth(double.tryParse(parts[2].trim())) : null,
    );
  }

  String encode() => widthFraction == null
      ? '${offset.dx},${offset.dy}'
      : '${offset.dx},${offset.dy},$widthFraction';

  /// Moves the form, leaving the remembered width untouched.
  ///
  /// The two gestures own one axis each, so the axes get one setter apiece
  /// rather than a shared `copyWith`: a nullable field cannot tell "not passed"
  /// from "cleared", and a single `copyWith` therefore let a park silently
  /// reset the width the user had just set (the width was read back as
  /// `null`/auto and written over the stored value).
  KeyboardFormGeometry withOffset(Offset offset) => KeyboardFormGeometry(
        offset: offset,
        widthFraction: widthFraction,
      );

  /// Widens/narrows the form, leaving the remembered position untouched. A
  /// null [widthFraction] is meaningful — it clears the preference, so the form
  /// goes back to sizing itself to the viewport.
  KeyboardFormGeometry withWidthFraction(double? widthFraction) =>
      KeyboardFormGeometry(offset: offset, widthFraction: widthFraction);

  @override
  bool operator ==(Object other) =>
      other is KeyboardFormGeometry &&
      other.offset == offset &&
      other.widthFraction == widthFraction;

  @override
  int get hashCode => Object.hash(offset, widthFraction);

  @override
  String toString() =>
      'KeyboardFormGeometry($offset, ${widthFraction ?? 'auto'})';
}
