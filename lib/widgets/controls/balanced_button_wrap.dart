import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Row counts for a BALANCED multi-row button block.
///
/// Flutter's [Wrap] fills each row to capacity and leaves the remainder on the
/// LAST row (e.g. 11 buttons at 6 columns → 6 + 5). The one-handed side panel
/// wants the opposite: the block must stay balanced (rows differ by at most
/// one) with the extra buttons on the BOTTOM rows ("除不尽的放下面的行中").
///
/// [n] is the button count, [capacity] the number that fit on one row. The row
/// count is the minimum the width allows (`ceil(n / capacity)`); the buttons
/// are then spread as evenly as possible, the last `n % rows` rows each taking
/// one extra. Examples: `(11, 6) → [5, 6]`, `(13, 6) → [4, 4, 5]`,
/// `(7, 6) → [3, 4]`, `(12, 6) → [6, 6]`.
List<int> balancedRowCounts(int n, int capacity) {
  if (n <= 0) return const <int>[];
  final int cap = capacity < 1 ? 1 : capacity;
  final int rows = (n + cap - 1) ~/ cap;
  final int base = n ~/ rows;
  final int rem = n % rows;
  return <int>[
    for (int i = 0; i < rows; i++) base + (i >= rows - rem ? 1 : 0),
  ];
}

/// Lays its children out in balanced rows (see [balancedRowCounts]) and aligns
/// every row within the block with [alignment].
///
/// The block is measured first, so a row is only ever given children that
/// actually fit — the layout can NEVER overflow horizontally, even when the
/// children have different widths (the desktop volume strip is 160px while
/// every other button is 48px). The block itself is positioned by its caller
/// (the side panel anchors it to the screen-centre-facing edge).
class BalancedButtonWrap extends MultiChildRenderObjectWidget {
  const BalancedButtonWrap({
    super.key,
    this.alignment = WrapAlignment.start,
    this.crossAxisAlignment = WrapCrossAlignment.center,
    this.spacing = 8,
    this.runSpacing = 6,
    super.children,
  });

  /// Row alignment inside the block (the block width is the widest row).
  final WrapAlignment alignment;

  /// Cross-axis alignment of each child inside its row.
  final WrapCrossAlignment crossAxisAlignment;

  final double spacing;
  final double runSpacing;

  @override
  RenderBalancedButtonWrap createRenderObject(BuildContext context) {
    return RenderBalancedButtonWrap(
      alignment: alignment,
      crossAxisAlignment: crossAxisAlignment,
      spacing: spacing,
      runSpacing: runSpacing,
      textDirection: Directionality.maybeOf(context),
    );
  }

  @override
  void updateRenderObject(
      BuildContext context, RenderBalancedButtonWrap renderObject) {
    renderObject
      ..alignment = alignment
      ..crossAxisAlignment = crossAxisAlignment
      ..spacing = spacing
      ..runSpacing = runSpacing
      ..textDirection = Directionality.maybeOf(context);
  }
}

/// Resolved balanced layout: row → child indices, per-row extents and the
/// resulting block size.
class _BalancedLayout {
  const _BalancedLayout({
    required this.rows,
    required this.rowWidths,
    required this.rowHeights,
    required this.width,
    required this.height,
  });

  final List<List<int>> rows;
  final List<double> rowWidths;
  final List<double> rowHeights;
  final double width;
  final double height;
}

class RenderBalancedButtonWrap extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, WrapParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, WrapParentData> {
  RenderBalancedButtonWrap({
    required WrapAlignment alignment,
    required WrapCrossAlignment crossAxisAlignment,
    required double spacing,
    required double runSpacing,
    required TextDirection? textDirection,
  })  : _alignment = alignment,
        _crossAxisAlignment = crossAxisAlignment,
        _spacing = spacing,
        _runSpacing = runSpacing,
        _textDirection = textDirection;

  WrapAlignment get alignment => _alignment;
  WrapAlignment _alignment;
  set alignment(WrapAlignment value) {
    if (_alignment == value) return;
    _alignment = value;
    markNeedsLayout();
  }

  WrapCrossAlignment get crossAxisAlignment => _crossAxisAlignment;
  WrapCrossAlignment _crossAxisAlignment;
  set crossAxisAlignment(WrapCrossAlignment value) {
    if (_crossAxisAlignment == value) return;
    _crossAxisAlignment = value;
    markNeedsLayout();
  }

  double get spacing => _spacing;
  double _spacing;
  set spacing(double value) {
    if (_spacing == value) return;
    _spacing = value;
    markNeedsLayout();
  }

  double get runSpacing => _runSpacing;
  double _runSpacing;
  set runSpacing(double value) {
    if (_runSpacing == value) return;
    _runSpacing = value;
    markNeedsLayout();
  }

  TextDirection? get textDirection => _textDirection;
  TextDirection? _textDirection;
  set textDirection(TextDirection? value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! WrapParentData) {
      child.parentData = WrapParentData();
    }
  }

  List<RenderBox> _childrenInOrder() {
    final List<RenderBox> out = <RenderBox>[];
    RenderBox? child = firstChild;
    while (child != null) {
      out.add(child);
      child = childAfter(child);
    }
    return out;
  }

  @override
  void performLayout() {
    final BoxConstraints constraints = this.constraints;
    final double maxWidth = constraints.maxWidth;
    final List<RenderBox> children = _childrenInOrder();
    final List<Size> sizes = <Size>[];
    for (final RenderBox child in children) {
      child.layout(BoxConstraints(maxWidth: maxWidth), parentUsesSize: true);
      sizes.add(child.size);
    }

    final _BalancedLayout layout = _resolve(sizes, maxWidth);
    size = constraints.constrain(Size(layout.width, layout.height));

    final bool ltr = _textDirection != TextDirection.rtl;
    double y = 0;
    for (int r = 0; r < layout.rows.length; r++) {
      final List<int> row = layout.rows[r];
      final double free = math.max(0, layout.width - layout.rowWidths[r]);
      final double startX = switch (_alignment) {
        WrapAlignment.start => ltr ? 0 : free,
        WrapAlignment.end => ltr ? free : 0,
        WrapAlignment.center => free / 2,
        // Not used by the side panel; degrade to start rather than crash.
        WrapAlignment.spaceBetween ||
        WrapAlignment.spaceAround ||
        WrapAlignment.spaceEvenly =>
          0,
      };
      double x = startX;
      for (final int index in row) {
        final RenderBox child = children[index];
        final WrapParentData parentData = child.parentData! as WrapParentData;
        parentData.offset = Offset(
          x,
          y + _crossOffset(layout.rowHeights[r], child.size.height),
        );
        x += child.size.width + _spacing;
      }
      y += layout.rowHeights[r] + _runSpacing;
    }
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final double maxWidth = constraints.maxWidth;
    final List<RenderBox> children = _childrenInOrder();
    final List<Size> sizes = <Size>[
      for (final RenderBox child in children)
        child.getDryLayout(BoxConstraints(maxWidth: maxWidth)),
    ];
    final _BalancedLayout layout = _resolve(sizes, maxWidth);
    return constraints.constrain(Size(layout.width, layout.height));
  }

  double _crossOffset(double rowHeight, double childHeight) {
    switch (_crossAxisAlignment) {
      case WrapCrossAlignment.start:
        return 0;
      case WrapCrossAlignment.center:
        return (rowHeight - childHeight) / 2;
      case WrapCrossAlignment.end:
        return rowHeight - childHeight;
    }
  }

  /// Pure row resolution: greedy capacity → balanced row counts → per-row
  /// extents, with a fit guard that pushes a child to the next row if a
  /// balanced row would overflow (only possible with non-uniform widths).
  _BalancedLayout _resolve(List<Size> sizes, double maxWidth) {
    final int n = sizes.length;
    if (n == 0) {
      return const _BalancedLayout(
        rows: <List<int>>[],
        rowWidths: <double>[],
        rowHeights: <double>[],
        width: 0,
        height: 0,
      );
    }

    // Greedy capacity: the number of leading children that fit on one row.
    int capacity = 0;
    double run = 0;
    for (int i = 0; i < n; i++) {
      final double w = sizes[i].width + (capacity > 0 ? _spacing : 0);
      if (capacity > 0 && run + w > maxWidth) break;
      run += w;
      capacity++;
    }
    if (capacity < 1) capacity = 1;

    final List<int> counts = balancedRowCounts(n, capacity);

    final List<List<int>> rows = <List<int>>[];
    int index = 0;
    for (int r = 0; r < counts.length && index < n; r++) {
      final List<int> row = <int>[];
      double w = 0;
      while (row.length < counts[r] && index < n) {
        final double cw = sizes[index].width + (row.isNotEmpty ? _spacing : 0);
        if (row.isNotEmpty && w + cw > maxWidth) break;
        w += cw;
        row.add(index);
        index++;
      }
      rows.add(row);
    }
    // Fit-guard leftovers (non-uniform widths): keep greedy rows so the layout
    // stays inside the panel instead of overflowing.
    while (index < n) {
      final List<int> row = <int>[];
      double w = 0;
      while (index < n) {
        final double cw = sizes[index].width + (row.isNotEmpty ? _spacing : 0);
        if (row.isNotEmpty && w + cw > maxWidth) break;
        w += cw;
        row.add(index);
        index++;
      }
      rows.add(row);
    }

    double blockWidth = 0;
    final List<double> rowWidths = <double>[];
    final List<double> rowHeights = <double>[];
    for (final List<int> row in rows) {
      double w = 0;
      double h = 0;
      for (int i = 0; i < row.length; i++) {
        w += sizes[row[i]].width + (i > 0 ? _spacing : 0);
        h = math.max(h, sizes[row[i]].height);
      }
      rowWidths.add(w);
      rowHeights.add(h);
      blockWidth = math.max(blockWidth, w);
    }
    double totalHeight = 0;
    for (int i = 0; i < rowHeights.length; i++) {
      totalHeight += rowHeights[i] + (i > 0 ? _runSpacing : 0);
    }

    return _BalancedLayout(
      rows: rows,
      rowWidths: rowWidths,
      rowHeights: rowHeights,
      width: blockWidth,
      height: totalHeight,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }
}
