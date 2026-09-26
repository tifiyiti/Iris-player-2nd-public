import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/features/paginated_browser/data_source/paginated_browser_data_source.dart';
import 'package:iris/features/paginated_browser/models/generic_browser_models.dart';
import 'package:iris/features/paginated_browser/paginated_browser_controller.dart';
import 'package:iris/features/paginated_browser/widgets/browser_bar_primitives.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/controls/balanced_button_wrap.dart';

/// Translucent plate of the floating bar, matching the control-group floating
/// switch's `Colors.black @ 0.55` but lighter, because this bar covers LIST ROWS
/// (text the user is trying to read) rather than a control panel.
const double _kScrimAlpha = 0.38;

/// Ceiling on the tiles sharing one row, so the bar is always two rows tall.
///
/// Derived, not chosen: the normal grid is 8 tiles and the selection grid 7, and
/// 8 ÷ 4 = 2. Without the cap the row count was an emergent property of the
/// available width, and the two grids' natural widths differ by 46px (454 vs
/// 408) — so a 412dp phone or a 430pt phone, both of which land squarely inside
/// that gap, rendered two rows normally and ONE row in selection mode. The bar
/// visibly jumped height the moment selection began, moving the control the
/// user had just aimed at. Row count is a design decision, not a division.
const int kFloatingGridMaxColumns = 4;

/// A square tile of the V3 floating grid. Exposed for tests: the grid is a grid
/// precisely because these are uniform squares, which is not observable from the
/// controls alone.
class FloatingGridTile extends StatelessWidget {
  const FloatingGridTile(
      {super.key, required this.child, this.scaleDown = false});

  final Widget child;
  final bool scaleDown;

  @override
  Widget build(BuildContext context) {
    return BrowserBarTile(scaleDown: scaleDown, child: child);
  }
}

/// V3 of the scenario play queue: a translucent, draggable grid of square tiles
/// floating OVER the list, with no bottom bar at all — the list takes the full
/// height and the controls hover on top of it.
///
/// Three properties are load-bearing:
///
/// * **Fractional placement.** The spot is a fraction (0..1) of the available
///   travel, never pixels, so the same remembered corner survives a dock resize,
///   a rotation and a restart (the rule the frame-tools float panel and the
///   control-group switch already follow).
/// * **One write per gesture.** Drag frames only move a [ValueNotifier]; the
///   fraction is committed once on release. Drift runs on the UI isolate, so a
///   per-frame write would stutter the whole drag.
/// * **Paint-only movement.** Both the drag and the press-scale are
///   `Transform`s fed a pre-built `child`, so the tiles — and the popup rows
///   they carry — are never rebuilt or re-laid-out while a finger is down.
///
/// The row count is pinned by [kFloatingGridMaxColumns] rather than left to the
/// available width, because the two grids hold different numbers of tiles and
/// would otherwise re-flow between each other.
///
/// The overflow rows are assembled in `build`, NOT in the `PopupMenuButton`'s
/// `itemBuilder`: a data source may read app state with `context.select` while
/// building its action list, and provider only allows that during a widget
/// build. `itemBuilder` runs on tap, which threw and left the menu unopenable.
class FloatingGridBar<T> extends HookWidget {
  /// Key on the transform that applies the bar's resting spot.
  ///
  /// Exposed because that transform is PAINT-only: the bar's LAYOUT box stays
  /// pinned at the host's origin, so anything that needs the bar's real on-screen
  /// position (a test, a future snap-to-edge affordance) has to read this rather
  /// than the widget's own box.
  static const Key offsetKey = ValueKey('floating_grid_bar_offset');

  final PaginatedBrowserController<T> controller;
  final PaginatedBrowserDataSource<T> dataSource;
  final VoidCallback? onClose;

  /// Locates the currently playing row; rendered only when the data source
  /// supports a current item.
  final VoidCallback? onGoToCurrent;

  /// Page-level chrome the overflow button owns (e.g. the queue's breadcrumb
  /// visibility checkbox).
  final List<PageAction> overflowActions;

  /// Remembered spot as a fraction of the available travel. Null centres the
  /// bar, which is also what a profile that has never been dragged gets from
  /// `AppState`.
  final Offset? offset;

  /// Called ONCE per drag, with the fraction the bar came to rest at. Null
  /// disables dragging altogether (the bar still renders, pinned to centre).
  final ValueChanged<Offset>? onMoved;

  /// Width the bar may lay its tiles out in, i.e. the width of the list area it
  /// floats over. Supplied by the page because the bar is a `Positioned` child
  /// and therefore cannot measure its own host.
  ///
  /// Without it the grid would size itself to its natural width and overflow a
  /// narrow host (the 240px side dock) instead of re-chunking into shorter rows.
  final double maxWidth;

  const FloatingGridBar({
    super.key,
    required this.controller,
    required this.dataSource,
    this.onClose,
    this.onGoToCurrent,
    this.overflowActions = const [],
    this.offset,
    this.onMoved,
    this.maxWidth = 0,
  });

  @override
  Widget build(BuildContext context) {
    useListenable(controller);

    // Selection-dependent actions are published the same way the other two bars
    // do it, so a custom selection action sees the current page's selection.
    dataSource.selectionForActions = _selectedItems();
    dataSource.clearSelectionForActions = controller.clearSelection;

    // Built HERE, inside build — see the class doc. `itemBuilder` must only hand
    // the finished list back.
    final overflowEntries = controller.isSelectionMode
        ? _selectionOverflowEntries(context)
        : _normalOverflowEntries(context);

    // Live fraction while a drag is in flight. Non-nullable because the resting
    // value is resolved immediately (the stored spot, or the centre default).
    final frac = useState<Offset>(offset ?? const Offset(0.5, 0.5));
    // Two INDEPENDENT questions, so two flags:
    //  * `dragging` — is a gesture live right now? Decides whether an incoming
    //    external offset may be adopted (see the effect below).
    //  * `moved` — did this gesture actually displace the bar? Decides whether
    //    there is anything worth committing, and is cleared by [commitDrag] so
    //    it never carries over. A tap that merely LOST the gesture arena reports
    //    `onPanCancel`, so without this a close-button tap would write the
    //    untouched spot back to the store.
    final moved = useState(false);
    final dragging = useState(false);
    // Bumped after layout so the bar repaints against its real measured size: a
    // fraction is only meaningful relative to the space it is applied to.
    final layoutTick = useState(0);
    final barKey = useMemoized(() => GlobalKey(), const []);

    /// Live size of the bar as actually laid out (after any scale-down).
    Size barSize() {
      final box = barKey.currentContext?.findRenderObject();
      return box is RenderBox && box.hasSize ? box.size : Size.zero;
    }

    /// The box the bar is allowed to travel inside: the hosting Stack — i.e. the
    /// list area this bar floats over.
    ///
    /// NOT `MediaQuery.sizeOf`: the bar is laid out inside the page, which is
    /// routinely far smaller than the window (the side dock is 240px wide, a
    /// popup a fraction of the screen). Measuring the viewport instead made the
    /// travel space wrong by that difference, so a drag moved the bar by a
    /// fraction of the SCREEN rather than of its own host.
    ///
    /// Walks up past the bar's own `Positioned`, exactly like
    /// `FrameToolsFloatPanel` / `ControlGroupFloatingButton` do in the player
    /// Stack. Falls back to the viewport only before the first layout.
    Size hostSize() {
      final box = barKey.currentContext?.findRenderObject();
      RenderBox? node = box is RenderBox ? box : null;
      while (node != null && node is! RenderStack) {
        node = node.parent is RenderBox ? node.parent as RenderBox : null;
      }
      if (node != null && node.hasSize) return node.size;
      final Size media = MediaQuery.sizeOf(context);
      final EdgeInsets safe = MediaQuery.paddingOf(context);
      return Size(
        (media.width - safe.horizontal).clamp(0.0, double.maxFinite),
        (media.height - safe.vertical).clamp(0.0, double.maxFinite),
      );
    }

    /// Travel the fraction is spread across: the host minus the bar. Never
    /// negative, so the bar cannot leave its host by construction — and a bar
    /// wider than its host simply has no horizontal travel rather than
    /// teleporting.
    Size travel() {
      final Size host = hostSize();
      final Size bar = barSize();
      return Size(
        (host.width - bar.width).clamp(0.0, double.maxFinite),
        (host.height - bar.height).clamp(0.0, double.maxFinite),
      );
    }

    /// Pixels to translate by for fraction [f].
    ///
    /// The bar's LAYOUT box already sits at the host's top-left corner (the
    /// `Align` below places it there), so the translation is `f * travel`:
    /// fraction 0 is flush with the corner, 1 is flush with the far corner. An
    /// earlier `(f - 0.5)` treated the layout box as if it were centred, which
    /// pushed fraction 0 half a travel PAST the corner — off-screen.
    Offset shiftOf(Offset f) {
      final Size space = travel();
      return Offset(f.dx * space.width, f.dy * space.height);
    }

    // Sizes only exist after layout, and the reveal happens a frame BEFORE that
    // layout lands — so adopt the stored fraction now and repaint once the boxes
    // are real. Re-runs whenever the host is resized, for the same reason: a
    // fraction is relative to the space it divides.
    final Size viewport = MediaQuery.sizeOf(context);
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Adopt the host's stored spot — including one that arrives AFTER a
        // drag, which is the normal case when the queue switches screen shape
        // (the spot is remembered per profile) or settings are imported. Only a
        // drag IN FLIGHT is off limits: yanking the bar out from under the
        // finger mid-gesture would fight the live fraction. Gating on "has ever
        // been dragged" instead stranded the previous shape's spot until the
        // page was fully remounted.
        if (!dragging.value) frac.value = offset ?? const Offset(0.5, 0.5);
        // Always bump: an identical value would not notify, and a fresh size is
        // exactly what this rebuild exists to pick up.
        layoutTick.value = layoutTick.value + 1;
      });
      return null;
    }, [viewport, offset]);

    void commitDrag() {
      dragging.value = false;
      // Never displaced: nothing new to remember, so leave the store alone.
      // The flag is PER GESTURE — `onPanCancel` also lands here (a tap that
      // lost the arena), so leaving it set would make every later tap commit
      // the spot it never moved.
      final displaced = moved.value;
      moved.value = false;
      if (!displaced) return;
      onMoved?.call(frac.value);
    }

    void onDragUpdate(DragUpdateDetails details) {
      dragging.value = true;
      moved.value = true;
      // Accumulate onto the LIVE fraction, never the one captured at build time:
      // several updates can land in one frame, before the rebuild, and a stale
      // base silently drops all but the last delta — the bar then lags the
      // finger.
      final Size space = travel();
      final Offset base = frac.value;
      frac.value = Offset(
        (base.dx + (space.width <= 0 ? 0 : details.delta.dx / space.width))
            .clamp(0.0, 1.0)
            .toDouble(),
        (base.dy + (space.height <= 0 ? 0 : details.delta.dy / space.height))
            .clamp(0.0, 1.0)
            .toDouble(),
      );
    }

    final Widget grid = Material(
      color: Colors.black.withValues(alpha: _kScrimAlpha),
      borderRadius: BorderRadius.circular(kBrowserBarTileSize / 2),
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.4),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(kBrowserBarTileSpacing / 2),
        child: controller.isSelectionMode
            ? _selectionGrid(context, overflowEntries)
            : _normalGrid(context, overflowEntries),
      ),
    );

    // A drag can start anywhere on the bar, while the tiles' own taps and popups
    // keep working: the recognizer is their ANCESTOR, so the two compete in the
    // gesture arena — a stationary press resolves to the tile's tap, movement
    // past the slop resolves to this pan. A drag never swallows a tap, and a tap
    // never nudges the bar. Omitted entirely when there is nowhere to commit to.
    final Widget draggable = onMoved == null
        ? grid
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: onDragUpdate,
            onPanEnd: (_) => commitDrag(),
            onPanCancel: commitDrag,
            child: grid,
          );

    // The `Transform` MUST be the outermost node of the bar. Hit testing walks
    // down the tree bounds-checking each box, and the bar's box stays at the
    // host origin — so any wrapper around the transform (an `Align`, a `Padding`)
    // bounds-checks against that origin box and rejects every tap aimed at the
    // bar's painted position, which is what made the controls unclickable while
    // still looking correct. With the transform outermost, its own (inverse-
    // transformed) hit test covers the painted spot.
    return ValueListenableBuilder<Offset>(
      valueListenable: frac,
      // `child` is passed through and never rebuilt: the tiles and the popup
      // rows they carry keep their elements for the whole drag.
      child: _DragLayer(
        key: barKey,
        dragging: dragging,
        child: draggable,
      ),
      builder: (context, live, child) {
        // Reading `layoutTick` is what makes a size change repaint against the
        // new travel, even though the fraction itself did not move.
        layoutTick.value;
        return Transform.translate(
          key: offsetKey,
          offset: shiftOf(live),
          child: child,
        );
      },
    );
  }

  Widget _normalGrid(
    BuildContext context,
    List<PopupMenuEntry<PageAction>> overflowEntries,
  ) {
    final t = getLocalizations(context);
    final tiles = <Widget>[
      FloatingGridTile(child: dataSource.buildSortMenu(context)),
      FloatingGridTile(child: buildBrowserPagePrevButton(dataSource)),
      BrowserBarWideTile(
        semanticLabel: t.browser_page_counter(
          dataSource.currentPage + 1,
          dataSource.totalPages,
        ),
        child: buildBrowserPageCounter(context, dataSource),
      ),
      FloatingGridTile(child: buildBrowserPageNextButton(dataSource)),
      BrowserBarWideTile(
        semanticLabel: t.browser_total_per_page(
            dataSource.totalItems, dataSource.pageSize),
        child: buildBrowserPerPageTotalChip(context, dataSource),
      ),
      if (buildBrowserGoCurrentButton(context, dataSource, onGoToCurrent) case
          final goCurrent?)
        FloatingGridTile(child: goCurrent),
      FloatingGridTile(
        child: _OverflowButton(entries: overflowEntries),
      ),
      if (onClose != null)
        FloatingGridTile(
          child: IconButton(
            tooltip: t.browser_close,
            icon: const Icon(Icons.close),
            onPressed: onClose,
          ),
        ),
    ];
    return _tileWrap(tiles, maxWidth);
  }

  Widget _selectionGrid(
    BuildContext context,
    List<PopupMenuEntry<PageAction>> overflowEntries,
  ) {
    final t = getLocalizations(context);
    final tiles = <Widget>[
      FloatingGridTile(
        child: IconButton(
          tooltip: t.browser_back,
          icon: const Icon(Icons.arrow_back),
          onPressed: controller.clearSelection,
        ),
      ),
      FloatingGridTile(child: buildBrowserPagePrevButton(dataSource)),
      BrowserBarWideTile(
        semanticLabel: t.browser_page_counter(
          dataSource.currentPage + 1,
          dataSource.totalPages,
        ),
        child: buildBrowserPageCounter(context, dataSource),
      ),
      FloatingGridTile(child: buildBrowserPageNextButton(dataSource)),
      BrowserBarWideTile(
        semanticLabel: t.browser_selected_count(
            controller.selectedIds.length, dataSource.totalItems),
        child: buildBrowserSelectedCountBadge(
            context, controller.selectedIds.length, dataSource),
      ),
      FloatingGridTile(
        child: _OverflowButton(entries: overflowEntries),
      ),
      if (onClose != null)
        FloatingGridTile(
          child: IconButton(
            tooltip: t.browser_close,
            icon: const Icon(Icons.close),
            onPressed: onClose,
          ),
        ),
    ];
    return _tileWrap(tiles, maxWidth);
  }

  /// Lays the tiles out in balanced rows, bounded so the grid is never wider
  /// than the space it may travel in.
  ///
  /// `BalancedButtonWrap` needs a bounded width to chunk rows against, and the
  /// bar gets that from the HOST's width (passed down from
  /// [PaginatedBrowserPage], the only place that knows it) rather than from its
  /// own position, which is unbounded. A `FittedBox` would be wrong here: it
  /// scales the bar to fill the space it can move in, leaving the horizontal
  /// travel at zero.
  ///
  /// [kFloatingGridMaxColumns] additionally pins the row count, so switching
  /// between the normal and selection grids cannot re-flow the block.
  Widget _tileWrap(List<Widget> tiles, double maxWidth) {
    final Widget grid = BalancedButtonWrap(
      alignment: WrapAlignment.center,
      spacing: kBrowserBarTileSpacing,
      runSpacing: kBrowserBarTileSpacing,
      maxColumns: kFloatingGridMaxColumns,
      children: tiles,
    );
    if (maxWidth <= 0 || !maxWidth.isFinite) return grid;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: grid,
    );
  }

  /// Page-level chrome first (it describes the bar the user is looking at), then
  /// the data source's own actions, then the trailing view toggles.
  List<PopupMenuEntry<PageAction>> _normalOverflowEntries(
    BuildContext context,
  ) {
    final dataActions = <PageAction>[
      ...dataSource.buildCustomPageActions(context),
      ...dataSource.buildTrailingPageActions(context),
    ];
    if (overflowActions.isEmpty) {
      return [for (final action in dataActions) _buildMenuItem(action)];
    }
    return [
      for (final action in overflowActions) _buildMenuItem(action),
      if (dataActions.isNotEmpty) const PopupMenuDivider(),
      for (final action in dataActions) _buildMenuItem(action),
    ];
  }

  /// Select-all / invert plus the data source's own selection actions.
  List<PopupMenuEntry<PageAction>> _selectionOverflowEntries(
    BuildContext context,
  ) {
    final t = getLocalizations(context);
    final allSelected = _areAllOnPageSelected();
    return [
      _buildMenuItem(PageAction(
        icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
        label: allSelected ? t.browser_deselect_all : t.browser_select_all,
        onPressed: () =>
            controller.toggleSelectAllOnPage(dataSource.items, dataSource),
      )),
      _buildMenuItem(PageAction(
        icon: const Icon(Icons.flip),
        label: t.browser_invert,
        onPressed: () =>
            controller.invertSelection(dataSource.items, dataSource),
      )),
      for (final action in dataSource.buildCustomSelectionActions(context))
        _buildMenuItem(PageAction(
          icon: action.icon,
          label: action.label,
          onPressed: () => unawaited(_runSelectionAction(context, action)),
        )),
    ];
  }

  Future<void> _runSelectionAction(
    BuildContext context,
    CustomSelectionAction<T> action,
  ) async {
    // Offline-grey, same rule as the other two bars: `enabled` is the static
    // flag, `enabledFor` is re-evaluated against the live selection.
    final selected = _selectedItems();
    final enabled =
        action.enabled && (action.enabledFor?.call(selected) ?? true);
    if (!enabled) return;
    final exit = await action.onPressed(context, selected);
    if (exit) controller.clearSelection();
  }

  PopupMenuItem<PageAction> _buildMenuItem(PageAction action) {
    // Offline-grey: an action with no handler renders disabled and does not
    // react to taps, matching the other bars' submenu rows.
    return PopupMenuItem<PageAction>(
      value: action,
      enabled: action.onPressed != null,
      child: Row(
        children: [
          action.icon,
          const SizedBox(width: 8),
          Expanded(child: Text(action.label)),
          // A `checked` action is a preference row: the whole row is the single
          // tap target (selecting it fires the action and closes the menu), so
          // the checkbox only mirrors the state and must not swallow the tap.
          if (action.checked != null)
            IgnorePointer(
              child: Checkbox(
                value: action.checked,
                onChanged: (_) {},
              ),
            ),
        ],
      ),
    );
  }

  bool _areAllOnPageSelected() {
    for (final item in dataSource.items) {
      if (!controller.selectedIds.contains(dataSource.getItemId(item))) {
        return false;
      }
    }
    return dataSource.items.isNotEmpty;
  }

  /// The CURRENT PAGE's selection — actions run against this set even though
  /// the count badge may show the global total.
  Set<T> _selectedItems() => dataSource.items
      .where(
          (item) => controller.selectedIds.contains(dataSource.getItemId(item)))
      .toSet();
}

/// The overflow button, split out so the tile wrapper and the menu stay in one
/// place. [entries] are already built — see [FloatingGridBar]'s doc.
class _OverflowButton extends StatelessWidget {
  const _OverflowButton({required this.entries});

  final List<PopupMenuEntry<PageAction>> entries;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<PageAction>(
      tooltip: getLocalizations(context).browser_more,
      icon: const Icon(Icons.more_vert),
      onSelected: (action) => action.onPressed?.call(),
      itemBuilder: (_) => entries,
    );
  }
}

/// Gives the bar its press-scale and keeps the gesture wiring out of the
/// widget's build body.
class _DragLayer extends StatelessWidget {
  const _DragLayer({
    super.key,
    required this.dragging,
    required this.child,
  });

  final ValueNotifier<bool> dragging;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: dragging,
      // Passed through: pressing the bar must not rebuild the tiles.
      child: child,
      builder: (context, isDragging, child) => Transform.scale(
        scale: isDragging ? 1.04 : 1.0,
        child: child,
      ),
    );
  }
}
