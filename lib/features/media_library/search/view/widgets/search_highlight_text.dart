import 'package:flutter/material.dart';
import 'package:iris/utils/escape_like.dart';

/// Renders [name] as rich text with the search-query matched substrings
/// background-highlighted (v10-D1). Uses the same matching semantics as the
/// DB/in-memory segments ([tokenizeQuery] + [highlightRanges]) so what was
/// matched is exactly what gets highlighted.
///
/// Falls back to a plain [Text] when [query] is empty or yields no matches.
class SearchHighlightText extends StatelessWidget {
  final String name;
  final String query;
  final int maxLines;

  const SearchHighlightText({
    super.key,
    required this.name,
    required this.query,
    this.maxLines = 3,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = tokenizeQuery(query);
    final ranges = highlightRanges(name, tokens);
    if (ranges.isEmpty) {
      return Text(name, maxLines: maxLines, overflow: TextOverflow.ellipsis);
    }

    final base = Theme.of(context).textTheme.bodyMedium;
    // Background + text-color emphasis (v10-D1): no bold — CJK glyphs often
    // lack a distinct bold weight, and bolding shifts glyph metrics in the
    // ellipsized tile. A tinted fill + primary text reads clearly on both
    // light and dark themes.
    final primary = Theme.of(context).colorScheme.primary;
    final highlight = TextStyle(
      backgroundColor: primary.withValues(alpha: 0.18),
      color: primary,
    );

    final spans = <TextSpan>[];
    var cursor = 0;
    for (final (start, end) in ranges) {
      if (start > cursor) {
        spans.add(TextSpan(text: name.substring(cursor, start)));
      }
      spans.add(TextSpan(text: name.substring(start, end), style: highlight));
      cursor = end;
    }
    if (cursor < name.length) {
      spans.add(TextSpan(text: name.substring(cursor)));
    }

    return RichText(
      text: TextSpan(style: base, children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}
