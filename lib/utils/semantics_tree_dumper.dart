import 'dart:async';
import 'dart:ui' show CheckedState, Tristate;

import 'package:flutter/rendering.dart';

import 'package:iris/utils/logger.dart';

final _log = const AreaKeyLog(LogKeys.axtreeDiag);

/// Dev-only diagnostics for the Windows `ui::AXTree` corruption
/// (flutter/flutter #182444 / #190344).
///
/// The engine's `Failed to update ui::AXTree` spam prints raw semantics node
/// ids that cannot be mapped to widgets by themselves. This dumper:
///
///  1. periodically serializes the FRAMEWORK semantics tree (id, parent,
///     rect, label, tags, flags, traversal identifiers) so a failing id can
///     be located even after the fact;
///  2. optionally runs a PER-FRAME diff watcher ([startFrameDiffWatcher])
///     that reports exactly which node changed which property (including
///     `value`, `scrollPosition`, transforms and the traversal graft
///     identifiers — the fields at the center of #190344) — this catches
///     both the residual high-frequency emitters and the structural event
///     that precedes the first engine corruption.
///
/// Read-only via [SemanticsNode.visitChildren], exactly like
/// `debugDumpSemanticsTree`. Enable via [axtreeDiagLogsEnabled] +
/// [startPeriodic] / [startFrameDiffWatcher] from `main()`.
abstract final class SemanticsTreeDumper {
  static Timer? _timer;
  static bool _lastHadOwner = false;
  static bool _a11yLogHooked = false;

  // ── per-frame diff state ──
  static bool _watching = false;
  static Map<int, _NodeSig> _lastSig = const {};
  static DateTime _bucketStart = DateTime.now();
  static int _loggedInBucket = 0;
  static int _suppressedInBucket = 0;

  /// Max diff lines emitted per wall-clock second; the rest is aggregated.
  static const int _maxDiffLinesPerSecond = 40;

  /// Starts a periodic full-tree dump (debug diagnostics only).
  static void startPeriodic({Duration interval = const Duration(seconds: 3)}) {
    _ensureAccessibilityLogHooked();
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _tick());
  }

  static void stopPeriodic() {
    _timer?.cancel();
    _timer = null;
  }

  /// Starts the per-frame semantics diff watcher (debug diagnostics only).
  ///
  /// Runs one tree walk per rendered frame and logs node-level property
  /// diffs, rate-limited to [_maxDiffLinesPerSecond] lines/s.
  static void startFrameDiffWatcher() {
    if (_watching) return;
    _watching = true;
    _scheduleNextFrame();
  }

  static void stopFrameDiffWatcher() => _watching = false;

  static void _scheduleNextFrame() {
    RendererBinding.instance.addPostFrameCallback((_) {
      if (!_watching) return;
      _snapshotAndDiff();
      _scheduleNextFrame();
    });
  }

  /// Logs accessibility-feature state transitions (semanticsEnabled /
  /// accessibleNavigation). Chained onto any existing callback.
  static void _ensureAccessibilityLogHooked() {
    if (_a11yLogHooked) return;
    _a11yLogHooked = true;
    final d = RendererBinding.instance.platformDispatcher;
    final prev = d.onAccessibilityFeaturesChanged;
    d.onAccessibilityFeaturesChanged = () {
      prev?.call();
      _log.i('AXTreeDiag features: sem=${d.semanticsEnabled} '
          'nav=${d.accessibilityFeatures.accessibleNavigation}');
    };
  }

  static String _a11yState() {
    final d = RendererBinding.instance.platformDispatcher;
    return 'sem=${d.semanticsEnabled} nav=${d.accessibilityFeatures.accessibleNavigation}';
  }

  /// Serializes the whole semantics tree once with a [reason] marker.
  static void dumpOnce(String reason) => _dump(reason);

  /// The semantics owner of the first render view (the modern non-deprecated
  /// path — the deprecated `RendererBinding.pipelineOwner` is detached from
  /// the tree and always reports a null owner).
  static SemanticsNode? get _rootNode {
    for (final view in RendererBinding.instance.renderViews) {
      final root = view.owner?.semanticsOwner?.rootSemanticsNode;
      if (root != null) return root;
    }
    return null;
  }

  static void _tick() {
    final hasRoot = _rootNode != null;
    if (!hasRoot) {
      if (_lastHadOwner) {
        _log.i('AXTreeDump: semantics disabled (owner/root gone)');
      }
      _lastHadOwner = false;
      return;
    }
    if (!_lastHadOwner) {
      _log.i('AXTreeDump: semantics enabled (owner ready)');
    }
    _lastHadOwner = true;
    _dump('periodic');
  }

  static Map<int, _NodeSig> _snapshot() {
    final root = _rootNode;
    if (root == null) return const {};
    final sigs = <int, _NodeSig>{};
    void walk(SemanticsNode node, int? parentId) {
      final children = <SemanticsNode>[];
      node.visitChildren((child) {
        children.add(child);
        return true;
      });
      sigs[node.id] = _NodeSig.of(node, parentId, children);
      for (final child in children) {
        walk(child, node.id);
      }
    }

    walk(root, null);
    return sigs;
  }

  static void _snapshotAndDiff() {
    final sigs = _snapshot();
    if (_lastSig.isEmpty && sigs.isEmpty) return;

    final now = DateTime.now();
    if (now.difference(_bucketStart).inMilliseconds >= 1000) {
      if (_suppressedInBucket > 0) {
        _log.i('AXDiff …+$_suppressedInBucket suppressed lines in bucket');
      }
      _bucketStart = now;
      _loggedInBucket = 0;
      _suppressedInBucket = 0;
    }

    void emit(String line) {
      if (_loggedInBucket < _maxDiffLinesPerSecond) {
        _loggedInBucket++;
        _log.i(line);
      } else {
        _suppressedInBucket++;
      }
    }

    final ids = <int>{...sigs.keys, ..._lastSig.keys}.toList()..sort();
    var changed = 0;
    for (final id in ids) {
      final next = sigs[id];
      final prev = _lastSig[id];
      if (next == null) {
        emit('AXDiff REMOVED #$id');
        changed++;
        continue;
      }
      if (prev == null) {
        emit('AXDiff ADDED #$id ${next.summary()}');
        changed++;
        continue;
      }
      for (final d in prev.diffAgainst(next)) {
        emit(d);
        changed++;
      }
    }
    if (changed > 0) {
      _log.i('AXDiff frame: $changed changed node(s) [${_a11yState()}]');
    }
    _lastSig = sigs;
  }

  static void _dump(String reason) {
    final root = _rootNode;
    if (root == null) {
      _log.i('AXTreeDump reason=$reason: no semantics tree');
      return;
    }

    final lines = <String>[];
    int count = 0;
    void walk(SemanticsNode node, int? parentId, int depth) {
      count++;
      final children = <SemanticsNode>[];
      node.visitChildren((child) {
        children.add(child);
        return true;
      });
      lines.add(_describe(node, parentId, depth, children.length));
      if (depth < 64) {
        for (final child in children) {
          walk(child, node.id, depth + 1);
        }
      }
    }

    walk(root, null, 0);
    _log.i('AXTreeDump reason=$reason nodes=$count root=${root.id} '
        '[${_a11yState()}]');
    // Chunked emission: one log record per ~100 lines keeps each record
    // comfortably below log-sink size limits.
    for (var i = 0; i < lines.length; i += 100) {
      final end = (i + 100).clamp(0, lines.length);
      _log.i(lines.sublist(i, end).join('\n'));
    }
  }

  static String _describe(
    SemanticsNode node,
    int? parentId,
    int depth,
    int childCount,
  ) {
    final indent = '  ' * depth;
    final label = node.label;
    final clipped =
        label.length > 48 ? '${label.substring(0, 48)}…' : label;
    final tags = node.tags?.map((t) => t.name).join(',') ?? '';
    final rect = node.rect;
    final flagNames = _flagNames(node);
    return '$indent#${node.id} parent=${parentId ?? "-"} '
        'rect=${rect.left.toStringAsFixed(0)},${rect.top.toStringAsFixed(0)},'
        '${rect.width.toStringAsFixed(0)}x${rect.height.toStringAsFixed(0)} '
        'ch=$childCount'
        '${clipped.isEmpty ? '' : ' label="$clipped"'}'
        '${tags.isEmpty ? '' : ' tags=[$tags]'}'
        '${flagNames.isEmpty ? '' : ' flags=${flagNames.join("|")}'}';
  }

  static List<String> _flagNames(SemanticsNode node) {
    final flags = node.flagsCollection;
    return <String>[
      if (flags.isButton) 'btn',
      if (flags.isTextField) 'text',
      if (flags.isSlider) 'slider',
      if (flags.isImage) 'img',
      if (flags.isHeader) 'hdr',
      if (flags.isSelected == Tristate.isTrue) 'sel',
      if (flags.isChecked != CheckedState.none) 'checked',
      if (flags.isFocused != Tristate.none) 'focusable',
      if (flags.hasImplicitScrolling) 'scroll',
      if (flags.scopesRoute) 'route',
      if (flags.isHidden) 'hidden',
      if (flags.isLiveRegion) 'live',
    ];
  }
}

/// Immutable per-node signature used by the per-frame diff watcher.
class _NodeSig {
  const _NodeSig({
    required this.id,
    required this.parent,
    required this.children,
    required this.rect,
    required this.transform,
    required this.label,
    required this.value,
    required this.textDirection,
    required this.scrollPosition,
    required this.flags,
    required this.traversalParent,
    required this.traversalChild,
    required this.tags,
  });

  factory _NodeSig.of(
      SemanticsNode node, int? parentId, List<SemanticsNode> children) {
    final t = node.transform;
    return _NodeSig(
      id: node.id,
      parent: parentId ?? -1,
      children: children.map((c) => c.id).toList(),
      rect: node.rect,
      transform: t?.toString(),
      label: node.label,
      value: node.value,
      textDirection: node.textDirection,
      scrollPosition: node.scrollPosition,
      flags: SemanticsTreeDumper._flagNames(node).join('|'),
      traversalParent: node.traversalParentIdentifier,
      traversalChild: node.traversalChildIdentifier,
      tags: node.tags?.map((x) => x.name).join(',') ?? '',
    );
  }

  final int id;
  final int parent;
  final List<int> children;
  final Rect rect;
  final String? transform;
  final String label;
  final String value;
  final TextDirection? textDirection;
  final double? scrollPosition;
  final String flags;
  final Object? traversalParent;
  final Object? traversalChild;
  final String tags;

  String summary() =>
      'parent=$parent rect=${_r(rect)} flags="$flags"'
      '${label.isEmpty ? '' : ' label="${_clip(label)}"'}';

  /// Returns one human-readable line per changed property, prefixed
  /// `AXDiff-STRUCT` for structural changes (parent/children/traversal graft
  /// identifiers — the events that precede engine tree corruption).
  List<String> diffAgainst(_NodeSig old) {
    final struct = <String>[];
    final props = <String>[];
    if (old.parent != parent) {
      struct.add('parent ${old.parent}→$parent');
    }
    if (!_listEquals(old.children, children)) {
      struct.add('children ${old.children}→$children');
    }
    if (old.traversalParent != traversalParent) {
      struct.add('travParent ${old.traversalParent}→$traversalParent');
    }
    if (old.traversalChild != traversalChild) {
      struct.add('travChild ${old.traversalChild}→$traversalChild');
    }
    if (old.rect != rect) {
      props.add('rect ${_r(old.rect)}→${_r(rect)}');
    }
    if (old.transform != transform) {
      props.add('transform ${_clip(old.transform ?? "null")}→'
          '${_clip(transform ?? "null")}');
    }
    if (old.label != label) {
      props.add('label "${_clip(old.label)}"→"${_clip(label)}"');
    }
    if (old.value != value) {
      props.add('value "${_clip(old.value)}"→"${_clip(value)}"');
    }
    if (old.textDirection != textDirection) {
      props.add('textDir ${old.textDirection}→$textDirection');
    }
    if (old.scrollPosition != scrollPosition) {
      props.add('scroll ${old.scrollPosition}→$scrollPosition');
    }
    if (old.flags != flags) {
      props.add('flags "${old.flags}"→"$flags"');
    }
    if (old.tags != tags) {
      props.add('tags [${old.tags}]→[$tags]');
    }
    final out = <String>[];
    if (struct.isNotEmpty) {
      out.add('AXDiff-STRUCT #$id ${struct.join("; ")}');
    }
    for (final p in props) {
      out.add('AXDiff #$id $p');
    }
    return out;
  }

  static String _r(Rect r) =>
      '${r.left.toStringAsFixed(1)},${r.top.toStringAsFixed(1)},'
      '${r.width.toStringAsFixed(1)}x${r.height.toStringAsFixed(1)}';

  static String _clip(String s) =>
      s.length > 40 ? '${s.substring(0, 40)}…' : s;

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
