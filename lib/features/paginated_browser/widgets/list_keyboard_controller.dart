import 'dart:async';

import 'package:flutter/foundation.dart';

/// Keyboard cursor + type-ahead buffer for a playlist-style list.
///
/// The cursor is a page-local row index (the focused row for PotPlayer `PL >`
/// navigation). It is intentionally NOT the selection set: `Ctrl+A`/`Ctrl+J`
/// drive the browser selection, while `↑/↓` move this single cursor, exactly
/// like PotPlayer's playlist highlight.
class ListKeyboardController {
  /// Current cursor row within the data source's `items`; null = no cursor yet.
  final ValueNotifier<int?> cursor = ValueNotifier<int?>(null);

  /// Whether the list currently holds keyboard focus.
  ///
  /// The cursor accent must answer "who owns ↑/↓ right now" at a glance: the
  /// row keeps its cursor while the list is unfocused (clicking the picture
  /// only moves focus), but the accent dims so it cannot lie about ownership.
  final ValueNotifier<bool> listActive = ValueNotifier<bool>(false);

  final StringBuffer _typeBuffer = StringBuffer();
  Timer? _typeTimer;

  void setCursor(int? index) {
    cursor.value = index;
  }

  /// Moves the cursor by [delta], clamped to `[0, length - 1]`. A null cursor
  /// starts at the first row for a downward move and the last row for an
  /// upward one (PotPlayer enters the list from the nearest edge).
  void moveCursor(int delta, int length) {
    if (length <= 0) {
      cursor.value = null;
      return;
    }
    final current = cursor.value;
    if (current == null) {
      cursor.value = delta >= 0 ? 0 : length - 1;
      return;
    }
    final next = (current + delta).clamp(0, length - 1);
    cursor.value = next;
  }

  void setFirst(int length) {
    if (length > 0) cursor.value = 0;
  }

  void setLast(int length) {
    if (length > 0) cursor.value = length - 1;
  }

  /// Appends [ch] to the type-ahead buffer (cleared after a short idle) and
  /// returns the index of the first [names] entry starting with the buffer.
  ///
  /// When a multi-character buffer matches nothing, the search restarts from
  /// just the newest character (standard incremental-search behavior).
  int? typeAhead(String ch, List<String> names) {
    _typeBuffer.write(ch.toLowerCase());
    _typeTimer?.cancel();
    _typeTimer = Timer(const Duration(milliseconds: 900), _typeBuffer.clear);
    final query = _typeBuffer.toString();
    var index = names.indexWhere((n) => n.toLowerCase().startsWith(query));
    if (index < 0 && query.length > 1) {
      _typeBuffer
        ..clear()
        ..write(ch.toLowerCase());
      final last = ch.toLowerCase();
      index = names.indexWhere((n) => n.toLowerCase().startsWith(last));
    }
    return index < 0 ? null : index;
  }

  void dispose() {
    _typeTimer?.cancel();
    cursor.dispose();
    listActive.dispose();
  }
}
