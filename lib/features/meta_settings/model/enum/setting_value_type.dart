/// Storage encoding of a setting's value in `setting_values.value`.
///
/// The codec (see `data/value_codec.dart`) owns the wire format; this enum
/// only declares which family a key belongs to so readers can decode safely.
enum SettingValueType {
  /// Dart bool, encoded as '1'/'0'.
  bool,

  /// Dart int, encoded as decimal string.
  int,

  /// Dart double, encoded as its `toString()` representation.
  double,

  /// Arbitrary string, stored verbatim.
  string,

  /// One of the declared enum value NAMES (see `enumValues` on the def).
  /// Stored by name so renaming Dart identifiers requires an explicit data
  /// migration instead of silently corrupting persisted choices.
  enumeration,

  /// Free-form JSON payload for composite settings (maps/lists).
  json,
}
