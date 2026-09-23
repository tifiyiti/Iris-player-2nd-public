/// Shared SQL `LIKE` escaping + tokenization helpers for media search.
///
/// Both the DAO (`media_nodes_dao.dart`) and the search data source
/// (`media_search_data_source.dart`) must agree on the matching semantics:
/// case-insensitive substring, whitespace-split AND tokens, `%`/`_` treated
/// as literals. Keeping them here guarantees DB rows and in-memory explicit
/// items use the exact same rules (v6-D4).
library;

/// Escapes a raw user string so `%`, `_` and the escape char itself are
/// treated as literals inside a `LIKE ... ESCAPE '\'` pattern.
///
/// Order matters: the backslash must be escaped FIRST so the subsequently
/// added `\%` / `\_` escapes are not themselves re-escaped.
String escapeLike(String raw) =>
    raw.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

/// Splits a raw query into search tokens: trimmed, whitespace-split, empty
/// tokens dropped (F-006). Case is NOT folded here — [matchesAllTokens] and
/// the DAO fold to lowercase at match time so the same tokens work for both.
List<String> tokenizeQuery(String raw) => raw
    .trim()
    .split(RegExp(r'\s+'))
    .where((s) => s.isNotEmpty)
    .toList();

/// Case-insensitive per-token AND substring match of [tokens] against
/// [value] (already the lowercase-normalized name, or lowercased here).
bool matchesAllTokens(String value, List<String> tokens) {
  if (tokens.isEmpty) return true;
  final lower = value.toLowerCase();
  return tokens.every((t) => lower.contains(t.toLowerCase()));
}

/// Case-insensitive highlight ranges of [tokens] within [value] as
/// `(start, end)` exclusive pairs, using the exact same matching semantics as
/// [matchesAllTokens] (substring per token, `%`/`_` treated as literals).
///
/// All occurrences of every token are collected; overlapping or touching
/// ranges are merged so callers render one contiguous highlight instead of
/// nested spans. Returns empty when nothing matches (or no tokens).
List<(int, int)> highlightRanges(String value, List<String> tokens) {
  final lower = value.toLowerCase();
  final ranges = <(int, int)>[];
  for (final t in tokens) {
    final term = t.toLowerCase();
    var from = 0;
    while (true) {
      final i = lower.indexOf(term, from);
      if (i < 0) break;
      ranges.add((i, i + term.length));
      from = i + term.length;
    }
  }
  if (ranges.length < 2) return ranges;
  ranges.sort((a, b) {
    final byStart = a.$1.compareTo(b.$1);
    return byStart != 0 ? byStart : a.$2.compareTo(b.$2);
  });
  final merged = <(int, int)>[ranges.first];
  for (final r in ranges.skip(1)) {
    final last = merged.last;
    if (r.$1 <= last.$2) {
      if (r.$2 > last.$2) {
        merged[merged.length - 1] = (last.$1, r.$2);
      }
    } else {
      merged.add(r);
    }
  }
  return merged;
}
