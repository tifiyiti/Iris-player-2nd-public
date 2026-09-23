import 'package:iris/features/meta_settings/model/enum/setting_value_type.dart';
import 'package:iris/features/meta_settings/model/setting_def.dart';

/// Metadata-path value validation — the shared enforcement point declared BY
/// [SettingDef] metadata (writable / clamps / enum whitelist).
///
/// The typed mutators keep their own inline clamps (legacy behavior must not
/// change); this guard guarantees the generic JSON path applies IDENTICAL
/// bounds because both derive from the same def declaration. The parity test
/// asserts the two agree on boundary values.
///
/// Error policy: coercion NEVER throws — an invalid value simply fails
/// (returns null) and the caller rejects the mutation. Settings writes are
/// user-driven UI actions; a silent reject with a log line beats a crash.
abstract final class ValueGuard {
  /// Returns the coerced, constraint-satisfied value, or null when [rawValue]
  /// is type-incompatible or violates a non-clampable constraint (enum
  /// whitelist). Clampable numeric violations are CORRECTED to the nearest
  /// bound — matching the typed mutators' clamp semantics.
  static Object? coerce(SettingDef def, Object? rawValue) {
    if (rawValue == null) return null;
    switch (def.valueType) {
      case SettingValueType.bool:
        return rawValue is bool ? rawValue : null;
      case SettingValueType.int:
        if (rawValue is! num || !rawValue.isFinite) return null;
        return _clamped(def, rawValue.toDouble())?.round();
      case SettingValueType.double:
        if (rawValue is! num || !rawValue.isFinite) return null;
        return _clamped(def, rawValue.toDouble());
      case SettingValueType.string:
        return rawValue is String ? rawValue : null;
      case SettingValueType.enumeration:
        final name = rawValue is String ? rawValue : null;
        if (name == null || !def.enumValues.contains(name)) return null;
        return name;
      case SettingValueType.json:
        return rawValue; // free-form payloads carry no declarative constraints
    }
  }

  static double? _clamped(SettingDef def, double v) {
    final min = def.clampMin;
    final max = def.clampMax;
    if (min == null && max == null) return v;
    if (v < (min ?? double.negativeInfinity)) return min!.toDouble();
    if (v > (max ?? double.infinity)) return max!.toDouble();
    return v;
  }
}
