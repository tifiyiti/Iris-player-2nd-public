/// Digit-aware "natural" string comparison: `2` sorts before `10`.
///
/// Splits the input into digit / non-digit runs; digit runs compare
/// numerically (leading zeros tie-break to the shorter run first), text runs
/// compare case-insensitively, falling back to raw comparison.
final _leadZeroRun = RegExp(r'^0+');

int vmNaturalCompare(String a, String b) {
  // Lowercase once up front: the hot loop used to copy the whole string per
  // character (O(n^2) allocations inside an O(n log n) sort).
  final al = a.toLowerCase();
  final bl = b.toLowerCase();
  var i = 0, j = 0;
  while (i < a.length && j < b.length) {
    final ad = _isDigit(a.codeUnitAt(i));
    final bd = _isDigit(b.codeUnitAt(j));
    if (ad && bd) {
      // Extract full numeric runs.
      var i2 = i;
      while (i2 < a.length && _isDigit(a.codeUnitAt(i2))) {
        i2++;
      }
      var j2 = j;
      while (j2 < b.length && _isDigit(b.codeUnitAt(j2))) {
        j2++;
      }
      final na = a.substring(i, i2);
      final nb = b.substring(j, j2);
      final cmp = _compareNumericRuns(na, nb);
      if (cmp != 0) return cmp;
      i = i2;
      j = j2;
    } else if (ad != bd) {
      // Digits before letters (matches most file-manager conventions).
      return ad ? -1 : 1;
    } else {
      final ca = al.codeUnitAt(i);
      final cb = bl.codeUnitAt(j);
      if (ca != cb) return ca.compareTo(cb);
      i++;
      j++;
    }
  }
  final byLen = (a.length - i).compareTo(b.length - j);
  if (byLen != 0) return byLen;
  return a.compareTo(b);
}

int _compareNumericRuns(String ra, String rb) {
  final ta = ra.replaceFirst(_leadZeroRun, '');
  final tb = rb.replaceFirst(_leadZeroRun, '');
  if (ta.length != tb.length) return ta.length.compareTo(tb.length);
  final cmp = ta.compareTo(tb); // same length → lexicographic == numeric
  if (cmp != 0) return cmp;
  return ra.length.compareTo(rb.length); // fewer leading zeros first
}

bool _isDigit(int code) => code >= 0x30 && code <= 0x39;
