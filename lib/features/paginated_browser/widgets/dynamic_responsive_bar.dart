import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/features/paginated_browser/data_source/paginated_browser_data_source.dart';
import 'package:iris/features/paginated_browser/models/generic_browser_models.dart';
import 'package:iris/features/paginated_browser/paginated_browser_controller.dart';
import 'package:iris/features/paginated_browser/widgets/browser_bar_primitives.dart';
import 'package:iris/utils/get_localizations.dart';

const double _kSpacing = 4.0;

class DynamicResponsiveBar<T> extends HookWidget {
  final PaginatedBrowserController<T> controller;
  final PaginatedBrowserDataSource<T> dataSource;
  final VoidCallback? onClose;
  final VoidCallback? onHomePage;
  final VoidCallback? onGoToCurrent;
  final bool showHomePage;
  final bool showBackButton;

  /// Index within the custom page actions where the "Go to current" button is
  /// inserted (0 = before all custom actions). Only meaningful when
  /// [onGoToCurrent] is set and [PaginatedBrowserDataSource.supportsCurrentItem]
  /// is true; other pages keep the default leading position.
  final int goToCurrentInsertIndex;

  const DynamicResponsiveBar({
    super.key,
    required this.controller,
    required this.dataSource,
    this.onClose,
    this.onHomePage,
    this.onGoToCurrent,
    this.showHomePage = true,
    this.showBackButton = true,
    this.goToCurrentInsertIndex = 0,
  });

  @override
  Widget build(BuildContext context) {
    useListenable(controller);

    // PageActions take a VoidCallback (no payload), so the selection they may
    // need is published on the data source before any of them renders. Fresh
    // by construction: this bar rebuilds on every selection change, and this
    // runs before either mode's action list is built.
    dataSource.selectionForActions = _selectedItems();
    dataSource.clearSelectionForActions = controller.clearSelection;

    final inSelection = controller.isSelectionMode;

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      child: inSelection
          ? _buildSelectionModeBar(context)
          : _buildNormalModeBar(context),
    );
  }

  // ─── BACK BUTTON DELEGATION ─────────────────────────────────────

  Future<void> _handleBack(BuildContext context) async {
    if (controller.isSearchActive) {
      controller.cancelSearch();
      return;
    }

    if (controller.isSelectionMode) {
      controller.clearSelection();
      return;
    }

    final handled = await dataSource.handleNavigationBack();
    if (!handled && onHomePage != null) {
      onHomePage!();
    }
  }

  // ─── NORMAL MODE ────────────────────────────────────────────────

  Widget _buildNormalModeBar(BuildContext context) {
    final t = getLocalizations(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final backBtn = showBackButton
            ? IconButton(
                tooltip: t.browser_back,
                icon: const Icon(Icons.arrow_back),
                onPressed: () => _handleBack(context),
              )
            : null;

        final homeBtn = showHomePage
            ? IconButton(
                tooltip: t.browser_home,
                icon: const Icon(Icons.home),
                onPressed: onHomePage,
              )
            : null;

        final sortMenu = dataSource.buildSortMenu(context);

        final searchBtn = dataSource.supportsSearch
            ? IconButton(
                tooltip: t.browser_search,
                icon: const Icon(Icons.search),
                onPressed: () {
                  dataSource.openSearchDialog(context, () {
                    controller.startSearch('');
                  });
                },
              )
            : null;

        final closeBtn = onClose != null
            ? IconButton(
                tooltip: t.browser_close,
                icon: const Icon(Icons.close),
                onPressed: onClose,
              )
            : null;

        final pageNav = _buildPageNavCompact(context);

        final perPageTotal = _buildPerPageTotalChip(context);

        final customActions = dataSource.buildCustomPageActions(context);
        final customActionBtns = _buildCustomActionIcons(customActions);

        // Far-right pinned actions (e.g. the scenario queue's dock/float
        // toggle): rendered after the page navigation, just left of close.
        final trailingActionBtns =
            _buildCustomActionIcons(dataSource.buildTrailingPageActions(context));

        final goCurrentBtn = buildBrowserGoCurrentButton(
            context, dataSource, onGoToCurrent);

        final actionCluster = [
          ...customActionBtns.take(goToCurrentInsertIndex),
          if (goCurrentBtn != null) goCurrentBtn,
          ...customActionBtns.skip(goToCurrentInsertIndex),
        ];

        // ── Tier 1: everything fits in one row ──
        // v9-D1: search is uniformly placed right after the items-per-page chip,
        // followed by the custom action cluster, in every tier.
        final allWidgets = [
          perPageTotal,
          if (searchBtn != null) searchBtn,
          ...actionCluster,
          if (backBtn != null) backBtn,
          sortMenu,
          if (homeBtn != null) homeBtn,
          pageNav,
        ];
        final oneRowWidth = _estimateWidth(allWidgets) + 48; // close btn width

        if (oneRowWidth <= constraints.maxWidth) {
          return Row(
            children: [
              perPageTotal,
              if (searchBtn != null) searchBtn,
              ...actionCluster,
              if (backBtn != null) backBtn,
              sortMenu,
              if (homeBtn != null) homeBtn,
              pageNav,
              const Spacer(),
              ...trailingActionBtns,
              if (closeBtn != null) closeBtn,
            ],
          );
        }

        // ── Tier 2: two rows ──
        final row1Widgets = [
          perPageTotal,
          if (searchBtn != null) searchBtn,
          ...actionCluster,
        ];
        final row1Width = _estimateWidth(row1Widgets);
        final row2Widgets = [
          if (backBtn != null) backBtn,
          sortMenu,
          if (homeBtn != null) homeBtn,
          pageNav,
        ];
        final row2Width = _estimateWidth(row2Widgets) +
            trailingActionBtns.fold<int>(0, (sum, w) => sum + 48) +
            48; // close btn width
        final maxRowWidth = row1Width > row2Width ? row1Width : row2Width;

        if (maxRowWidth <= constraints.maxWidth) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  perPageTotal,
                  if (searchBtn != null) searchBtn,
                  ...actionCluster,
                ],
              ),
              Row(
                children: [
                  if (backBtn != null) backBtn,
                  sortMenu,
                  if (homeBtn != null) homeBtn,
                  pageNav,
                  const Spacer(),
                  ...trailingActionBtns,
                  if (closeBtn != null) closeBtn,
                ],
              ),
            ],
          );
        }

        // ── Tier 3: wrap fallback ──
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: _kSpacing,
              runSpacing: _kSpacing,
              children: [
                perPageTotal,
                if (searchBtn != null) searchBtn,
                ...actionCluster,
              ],
            ),
            Row(
              children: [
                if (backBtn != null) backBtn,
                sortMenu,
                if (homeBtn != null) homeBtn,
                pageNav,
                const Spacer(),
                ...trailingActionBtns,
                if (closeBtn != null) closeBtn,
              ],
            ),
          ],
        );
      },
    );
  }

  // ─── SELECTION MODE ─────────────────────────────────────────────

  Widget _buildSelectionModeBar(BuildContext context) {
    final t = getLocalizations(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final quitBtn = IconButton(
          tooltip: t.browser_back,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => controller.clearSelection(),
        );

        final homeBtn = showHomePage
            ? IconButton(
                tooltip: t.browser_home,
                icon: const Icon(Icons.home),
                onPressed: onHomePage,
              )
            : null;

        final closeBtn = onClose != null
            ? IconButton(
                tooltip: t.browser_close,
                icon: const Icon(Icons.close),
                onPressed: onClose,
              )
            : null;

        final selectAllBtn = IconButton(
          tooltip: _areAllOnPageSelected()
              ? t.browser_deselect_all
              : t.browser_select_all,
          icon: Icon(_areAllOnPageSelected() ? Icons.deselect : Icons.select_all),
          onPressed: () => controller.toggleSelectAllOnPage(dataSource.items, dataSource),
        );

        final invertBtn = IconButton(
          tooltip: t.browser_invert,
          icon: const Icon(Icons.flip),
          onPressed: () => controller.invertSelection(dataSource.items, dataSource),
        );

        final customSelActions = dataSource.buildCustomSelectionActions(context);

        final pageNav = _buildPageNavCompact(context);

        final selectedCount = _buildSelectedCountBadge(context);

        final customSelBtns = _buildCustomSelectionIcons(customSelActions, context);

        // ── Tier 1: everything in one row ──
        final allWidgets = [
          quitBtn,
          if (homeBtn != null) homeBtn,
          pageNav,
          selectAllBtn,
          invertBtn,
          ...customSelBtns,
          selectedCount,
        ];
        final oneRowWidth = _estimateWidth(allWidgets) + 48; // close btn

        if (oneRowWidth <= constraints.maxWidth) {
          return Row(
            children: [
              quitBtn,
              if (homeBtn != null) homeBtn,
              pageNav,
              selectAllBtn,
              invertBtn,
              ...customSelBtns,
              selectedCount,
              const Spacer(),
              if (closeBtn != null) closeBtn,
            ],
          );
        }

        // ── Tier 2: two rows ──
        final row1Widgets = [selectAllBtn, invertBtn, ...customSelBtns];
        final row1Width = _estimateWidth(row1Widgets);
        final row2Widgets2 = [
          quitBtn,
          if (homeBtn != null) homeBtn,
          pageNav,
          selectedCount,
        ];
        final row2Width = _estimateWidth(row2Widgets2) + 48; // close btn
        final maxRowWidth = row1Width > row2Width ? row1Width : row2Width;

        if (maxRowWidth <= constraints.maxWidth) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [selectAllBtn, invertBtn, ...customSelBtns],
              ),
              Row(
                children: [
                  quitBtn,
                  if (homeBtn != null) homeBtn,
                  pageNav,
                  selectedCount,
                  const Spacer(),
                  if (closeBtn != null) closeBtn,
                ],
              ),
            ],
          );
        }

        // ── Tier 3: wrap fallback ──
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: _kSpacing,
              runSpacing: _kSpacing,
              children: [selectAllBtn, invertBtn, ...customSelBtns],
            ),
            Row(
              children: [
                quitBtn,
                if (homeBtn != null) homeBtn,
                pageNav,
                selectedCount,
                const Spacer(),
                if (closeBtn != null) closeBtn,
              ],
            ),
          ],
        );
      },
    );
  }

  // ─── SHARED HELPERS ─────────────────────────────────────────────

  bool _areAllOnPageSelected() {
    for (final item in dataSource.items) {
      if (!controller.selectedIds.contains(dataSource.getItemId(item))) {
        return false;
      }
    }
    return dataSource.items.isNotEmpty;
  }

  Widget _buildPageNavCompact(BuildContext context) =>
      buildBrowserPageNav(context, dataSource);

  Widget _buildPerPageTotalChip(BuildContext context) =>
      buildBrowserPerPageTotalChip(context, dataSource);

  Widget _buildSelectedCountBadge(BuildContext context) =>
      buildBrowserSelectedCountBadge(
          context, controller.selectedIds.length, dataSource);

  List<Widget> _buildCustomActionIcons(List<PageAction> actions) {
    return actions.map((action) {
      if (action.subActions != null) {
        return PopupMenuButton<PageAction>(
          tooltip: action.label,
          icon: action.icon,
          onSelected: (subAction) => subAction.onPressed?.call(),
          itemBuilder: (context) {
            return action.subActions!.map((subAction) {
              return PopupMenuItem<PageAction>(
                value: subAction,
                // Offline-grey: a submenu entry with no handler renders
                // disabled and has no tap reaction.
                enabled: subAction.onPressed != null,
                child: Row(
                  children: [
                    subAction.icon,
                    const SizedBox(width: 8),
                    Text(subAction.label),
                  ],
                ),
              );
            }).toList();
          },
        );
      }
      return IconButton(
        tooltip: action.label,
        icon: action.icon,
        onPressed: action.onPressed,
      );
    }).toList();
  }

  /// The CURRENT PAGE's selection: `selectedIds` intersected with the rows
  /// actually rendered. The count badge may show the global total, but every
  /// action runs against this set — counting scope and action scope differ by
  /// design.
  Set<T> _selectedItems() => dataSource.items
      .where((item) => controller.selectedIds.contains(dataSource.getItemId(item)))
      .toSet();

  List<Widget> _buildCustomSelectionIcons(
    List<CustomSelectionAction<T>> actions,
    BuildContext context,
  ) {
    if (actions.isEmpty) return [];

    final selectedItems = _selectedItems();

    return actions.map((action) {
      // Offline-grey: standard disabled button, no tap reaction. enabledFor
      // re-evaluates on every selection change (the bar listens to the
      // controller), so play actions track storage connectivity live.
      final enabled =
          action.enabled && (action.enabledFor?.call(selectedItems) ?? true);
      return IconButton(
        tooltip: action.label,
        icon: action.icon,
        onPressed: !enabled
            ? null
            : () async {
                final exit = await action.onPressed(context, selectedItems);
                if (exit) controller.clearSelection();
              },
      );
    }).toList();
  }

  double _estimateWidth(List<Widget> widgets) {
    double total = 0;
    for (final w in widgets) {
      if (w is IconButton) {
        total += 48; // default Flutter IconButton size
      } else if (w is Row) {
        total += kBrowserBarPageNavWidth;
      } else if (w is PopupMenuButton) {
        total += 48;
      } else if (w is ConstrainedBox) {
        // v9-D2: the items-per-page chip has a fixed width; estimate it as such.
        total += kBrowserBarPerPageTextWidth;
      } else if (w is InkWell) {
        total += kBrowserBarPerPageTextWidth;
      } else {
        total += kBrowserBarSelectedCountWidth;
      }
      total += _kSpacing;
    }
    return total;
  }
}
