/// Auto-naming for virtual-media rules (`rule` + incrementing int).
///
/// Pure functions only — no widgets, no DB. Persistence of the
/// `globalCounter` watermark lives in `VmPrefs` (AUX row
/// `virtualmedia.nameCounter`); the strategy/prefix/format choices live in
/// the metadata-driven settings rows. Gate-OFF runs degrade to the code
/// defaults (prefix `rule`, format `raw`, strategy `maxPlusOne`).
library;

/// Default name prefix when the configured one is empty.
const String kVmNamePrefixDefault = 'rule';

/// Naming strategies for the numeric suffix.
enum VmNamingStrategy {
  /// Max existing suffix + 1; deleted numbers are never reused.
  maxPlusOne,

  /// Smallest unused positive int (fills gaps left by deletions).
  reuseGap,

  /// Monotonic watermark persisted across deletions (`counterHint + 1`,
  /// bumped past any collision with existing names).
  globalCounter,
}

/// Parses [VmNamingStrategy] from a stored row value; unknown degrades to
/// [VmNamingStrategy.maxPlusOne] — corrupt settings never break naming.
VmNamingStrategy parseVmNamingStrategy(String? raw) {
  return VmNamingStrategy.values
          .where((e) => e.name == raw)
          .firstOrNull ??
      VmNamingStrategy.maxPlusOne;
}

/// Normalizes a configured prefix: blank degrades to `rule`.
String normalizeVmPrefix(String? raw) {
  final t = (raw ?? '').trim();
  return t.isEmpty ? kVmNamePrefixDefault : t;
}

/// Normalizes a number-format token: unknown degrades to `raw`.
String normalizeVmNumberFormat(String? raw) {
  return switch (raw) {
    'pad2' || 'pad3' || 'pad4' => raw!,
    _ => 'raw',
  };
}

/// Zero-pads [n] per [format] (`raw`/`pad2`/`pad3`/`pad4`); longer numbers
/// are never truncated.
String padNumber(int n, String format) {
  final width = switch (format) {
    'pad2' => 2,
    'pad3' => 3,
    'pad4' => 4,
    _ => 0,
  };
  final s = '$n';
  if (width <= 0 || s.length >= width) return s;
  return s.padLeft(width, '0');
}

/// Extracts the numeric suffix of [name] under [prefix]; returns -1 when
/// [name] is not exactly `prefix + digits` (hand-made names and the built-in
/// `_dirs_as_virtual` seed never participate in auto-numbering).
int parseVmSuffix(String name, String prefix) {
  final p = normalizeVmPrefix(prefix);
  if (!name.startsWith(p)) return -1;
  final tail = name.substring(p.length);
  if (tail.isEmpty) return -1;
  for (var i = 0; i < tail.length; i++) {
    final c = tail.codeUnitAt(i);
    if (c < 0x30 || c > 0x39) return -1;
  }
  return int.tryParse(tail) ?? -1;
}

/// Computes the next rule name. For `globalCounter`, [counterHint] is the
/// persisted watermark (0 when unset); the result is bumped past any
/// existing collision so a lowered watermark can never duplicate a name.
String nextVmRuleName({
  required Iterable<String> existing,
  required String prefix,
  required String numberFormat,
  required VmNamingStrategy strategy,
  int? counterHint,
}) {
  final p = normalizeVmPrefix(prefix);
  final fmt = normalizeVmNumberFormat(numberFormat);
  final used = <int>{
    for (final name in existing)
      if (parseVmSuffix(name, p) > 0) parseVmSuffix(name, p),
  };
  int n;
  switch (strategy) {
    case VmNamingStrategy.reuseGap:
      n = 1;
      while (used.contains(n)) {
        n++;
      }
    case VmNamingStrategy.globalCounter:
      n = (counterHint ?? 0) + 1;
      if (n < 1) n = 1;
      while (used.contains(n)) {
        n++;
      }
    case VmNamingStrategy.maxPlusOne:
      var max = 0;
      for (final v in used) {
        if (v > max) max = v;
      }
      n = max + 1;
  }
  return '$p${padNumber(n, fmt)}';
}

/// Local-time creation stamp precise to milliseconds:
/// `yyyy-MM-dd HH:mm:ss.SSS` (default description for new/copied rules).
String formatVmTimestamp(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  String three(int v) => v.toString().padLeft(3, '0');
  return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${three(t.millisecond)}';
}
