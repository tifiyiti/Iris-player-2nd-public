import 'dart:convert';

import 'package:iris/features/meta_settings/model/enum/setting_value_type.dart';
import 'package:iris/utils/logger.dart';

final metaLog = AreaKeyLog(LogKeys.legacyDb);

/// Bidirectional encoder between Dart values and the TEXT column form.
///
/// DIALECT BOUNDARY: this is the **AUXILIARY (`<domain>.`) row dialect**.
/// `app.*` snapshot rows do NOT use ValueCodec — they store `jsonEncode` of
/// the field value (see StateBridge/StateBridge.encodeField), so a bool there
/// is `'true'`/`'false'`, never `'1'`/`'0'`. Mixing the two silently drops
/// rows on load.
///
/// Wire format by family:
///  - bool         → '1' | '0'
///  - int          → decimal string
///  - double       → `toString()` round-trip form
///  - string       → verbatim
///  - enumeration  → enum value NAME, verbatim
///  - json         → `jsonEncode` payload (map/list/scalar)
///
/// Error policy — "define errors out of existence": malformed persisted data
/// NEVER throws at load time. Decoders log a warning and return the caller's
/// fallback so a single corrupt row cannot break settings bootstrapping.
abstract final class ValueCodec {
  /// Encodes [value] for the column. Returns null when the value's runtime
  /// type does not match the declared family (logged, treated as absent).
  static String? encode(SettingValueType type, Object? value) {
    if (value == null) return null;
    switch (type) {
      case SettingValueType.bool:
        if (value is bool) return value ? '1' : '0';
        break;
      case SettingValueType.int:
        if (value is int) return value.toString();
        break;
      case SettingValueType.double:
        if (value is double || value is int) return value.toString();
        break;
      case SettingValueType.string:
      case SettingValueType.enumeration:
        if (value is String) return value;
        break;
      case SettingValueType.json:
        try {
          return jsonEncode(value);
        } catch (e) {
          metaLog.w('ValueCodec.encode(jsonEncode failed): $e');
          return null;
        }
    }
    metaLog.w(
      'ValueCodec.encode: type mismatch for $type (got ${value.runtimeType})',
    );
    return null;
  }

  static bool decodeBool(String? raw, {bool fallback = false}) => switch (raw) {
        '1' => true,
        '0' => false,
        _ => _warn('bool', raw, fallback),
      };

  static int decodeInt(String? raw, {int fallback = 0}) =>
      int.tryParse(raw ?? '') ?? _warn('int', raw, fallback);

  static double decodeDouble(String? raw, {double fallback = 0.0}) =>
      double.tryParse(raw ?? '') ??
      (raw == null ? fallback : _warn('double', raw, fallback));

  /// Verbatim string; malformed input is impossible here, null stays null.
  static String? decodeString(String? raw) => raw;

  /// JSON array of strings (defs.enum_values / platforms columns).
  static List<String> decodeStringList(String? raw,
      {List<String> fallback = const <String>[]}) {
    if (raw == null) return fallback;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<String>().toList(growable: false);
      }
    } catch (e) {
      metaLog.w('ValueCodec.decodeStringList($raw): $e');
    }
    return fallback;
  }

  /// Generic JSON payload (composite settings).
  static Object? decodeJson(String? raw) {
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } catch (e) {
      metaLog.w('ValueCodec.decodeJson: $e');
      return null;
    }
  }

  static T _warn<T>(String family, String? raw, T fallback) {
    metaLog.w('ValueCodec.decode($family): malformed "$raw", using fallback');
    return fallback;
  }
}
