import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/features/paginated_browser/data_source/paginated_browser_data_source.dart';
import 'package:iris/features/paginated_browser/models/generic_browser_models.dart';
import 'package:iris/features/paginated_browser/paginated_browser_controller.dart';
import 'package:iris/features/paginated_browser/widgets/browser_bar_primitives.dart';
import 'package:iris/utils/get_localizations.dart';

const double _kSpacing = 4.0;

/// Single-row toolbar: the scenario play queue's V2 layout.
///
/// The whole point is that the bar NEVER reflows. It keeps exactly the
/// navigation controls inline — sort, page navigation, total/per-page, and
/// go-to-current — and folds every other action (the data source's custom
/// actions, the trailing view toggles, and the page-level [overflowActions])
/// into one overflow button.
///
/// Two properties make that safe:
///
/// * The leading cluster is a `Flexible` + `FittedBox(scaleDown)`, so a narrow
///   host (the side dock goes down to 240px, narrower than the controls need)
///   shrinks the counters instead of wrapping or overflowing. The overflow and
///   close buttons sit outside it and keep their full tap targets.
/// * The controls themselves are the SAME widgets the responsive bar renders
///   (see [browser_bar_primitives]), so switching layouts cannot change what a
///   control does — only where it lives.
class CompactSingleRowBar<T> extends HookWidget {
  final PaginatedBrowserController<T> controller;
  final PaginatedBrowserDataSource<T> dataSource;
  final VoidCallback? onClose;

  /// Locates the currently playing row. Rendered only when the data source
  /// supports a current item.
  final VoidCallback? onGoToCurrent;

  /// Page-level chrome the overflow button owns (e.g. the queue's breadcrumb
  /// visibility checkbox). The responsive bar has no overflow button and
  /// therefore ignores these entirely.
  final List<PageAction> overflowActions;

  const CompactSingleRowBar({
    super.key,
    required this.controller,
    required this.dataSource,
    this.onClose,
    this.onGoToCurrent,
    this.overflowActions = const [],
  });

  @override
  Widget build(BuildContext context) {
    useListenable(controller);

    // Selection-dependent actions are published the same way the responsive
    // bar does it, so a custom selection action sees the current page's
    // selection when the overflow menu is finally tapped.
    dataSource.selectionForActions = _selectedItems();
    dataSource.clearSelectionForActions = controller.clearSelection;

    // Assemble the overflow rows HERE, inside build, and hand the finished list
    // to PopupMenuButton. A data source may read app state with `context.select`
    // while building its action list, and provider only permits that during a
    // widget build — the tap that opens the menu is not one. Deferring the
    // assembly into `itemBuilder` (which runs on tap) therefore throws
    // "Tried to use `context.select` outside of the build method" and the menu
    // never opens. The responsive bar gets this for free by calling the same
    // two methods from its own build; matching that is what keeps V2 working.
    final overflowEntries = controller.isSelectionMode
        ? _selectionOverflowEntries(context)
        : _normalOverflowEntries(context);

    return Container(
      padding: const EdgeInsets.all(4),
      child: controller.isSelectionMode
          ? _buildSelectionRow(context, overflowEntries)
          : _buildNormalRow(context, overflowEntries),
    );
  }

  Widget _buildNormalRow(
    BuildContext context,
    List<PopupMenuEntry<PageAction>> overflowEntries,
  ) {
    final goCurrent =
        buildBrowserGoCurrentButton(context, dataSource, onGoToCurrent);

    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  dataSource.buildSortMenu(context),
                  buildBrowserPageNav(context, dataSource),
                  buildBrowserPerPageTotalChip(context, dataSource),
                  if (goCurrent != null) goCurrent,
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: _kSpacing),
        _buildOverflowButton(context, overflowEntries),
        if (onClose != null)
          IconButton(
            tooltip: getLocalizations(context).browser_close,
            icon: const Icon(Icons.close),
            onPressed: onClose,
          ),
      ],
    );
  }

  Widget _buildSelectionRow(
    BuildContext context,
    List<PopupMenuEntry<PageAction>> overflowEntries,
  ) {
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: getLocalizations(context).browser_back,
                    icon: const Icon(Icons.arrow_back),
                    onPressed: controller.clearSelection,
                  ),
                  buildBrowserPageNav(context, dataSource),
                  buildBrowserSelectedCountBadge(
                      context, controller.selectedIds.length, dataSource),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: _kSpacing),
        _buildOverflowButton(context, overflowEntries),
        if (onClose != null)
          IconButton(
            tooltip: getLocalizations(context).browser_close,
            icon: const Icon(Icons.close),
            onPressed: onClose,
          ),
      ],
    );
  }

  /// Page-level chrome first (it describes the bar the user is looking at),
  /// then the data source's own actions, then the trailing view toggles.
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
    // Offline-grey, same rule as the responsive bar: `enabled` is the static
    // flag, `enabledFor` is re-evaluated against the live selection.
    final selected = _selectedItems();
    final enabled =
        action.enabled && (action.enabledFor?.call(selected) ?? true);
    if (!enabled) return;
    final exit = await action.onPressed(context, selected);
    if (exit) controller.clearSelection();
  }

  Widget _buildOverflowButton(
    BuildContext context,
    List<PopupMenuEntry<PageAction>> entries,
  ) {
    return PopupMenuButton<PageAction>(
      tooltip: getLocalizations(context).browser_more,
      icon: const Icon(Icons.more_vert),
      onSelected: (action) => action.onPressed?.call(),
      // The rows are already built (see `build`); `itemBuilder` must not
      // rebuild them, or the data source's `context.select` would run on tap.
      itemBuilder: (_) => entries,
    );
  }

  PopupMenuItem<PageAction> _buildMenuItem(PageAction action) {
    // Offline-grey: an action with no handler renders disabled and does not
    // react to taps, matching the responsive bar's submenu rows.
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
      .where((item) => controller.selectedIds.contains(dataSource.getItemId(item)))
      .toSet();
}
