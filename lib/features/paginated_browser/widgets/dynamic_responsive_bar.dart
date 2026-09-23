import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/features/paginated_browser/data_source/paginated_browser_data_source.dart';
import 'package:iris/features/paginated_browser/models/generic_browser_models.dart';
import 'package:iris/features/paginated_browser/paginated_browser_controller.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/adaptive/keyboard_form_shell.dart';

const double _kSpacing = 4.0;
const double _kPageNavWidth = 108.0;
const double _kPerPageTextWidth = 64.0;
const double _kSelectedCountWidth = 80.0;

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

        final goCurrentBtn = onGoToCurrent != null && dataSource.supportsCurrentItem
            ? IconButton(
                tooltip: getLocalizations(context).browser_go_current,
                icon: const Icon(Icons.my_location),
                onPressed: onGoToCurrent,
              )
            : null;

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

  Widget _buildPageNavCompact(BuildContext context) {
    final prevBtn = IconButton(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      icon: const Icon(Icons.navigate_before),
      onPressed: dataSource.currentPage > 0
          ? () => dataSource.fetchPage(dataSource.currentPage - 1, dataSource.pageSize)
          : null,
    );

    final nextBtn = IconButton(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      icon: const Icon(Icons.navigate_next),
      onPressed: dataSource.currentPage < dataSource.totalPages - 1
          ? () => dataSource.fetchPage(dataSource.currentPage + 1, dataSource.pageSize)
          : null,
    );

    // The toolbar sits outside the browser list's `Material`, so a bare `Text`
    // would inherit the outermost Material's DefaultTextStyle (the app theme)
    // rather than this toolbar's theme. On the dark docked panel that rendered
    // app-dark text on a black background — invisible. Pin the foreground to
    // the toolbar theme explicitly.
    final pageText = InkWell(
      onTap: () => _handleNumericJump(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: Text(
          '${dataSource.currentPage + 1}/${dataSource.totalPages}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: Theme.of(context).textTheme.bodyMedium?.color,
          ),
        ),
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [prevBtn, pageText, nextBtn],
    );
  }

  Widget _buildPerPageTotalChip(BuildContext context) {
    // v9-D2: fixed width so the chip occupies the same space regardless of how
    // many digits the total count has (matches _estimateWidth's InkWell=100).
    return ConstrainedBox(
      constraints: BoxConstraints.tightFor(width: _kPerPageTextWidth),
      child: InkWell(
        onTap: () => _handleChangePageSize(context),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${dataSource.totalItems}/${dataSource.pageSize}',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: Theme.of(context).colorScheme.primary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedCountBadge(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline, size: 18),
          const SizedBox(width: 4),
          Text(
            '${controller.selectedIds.length}/${dataSource.totalItems}',
            // Same reason as the page counter: pin to the toolbar theme
            // instead of the ambient DefaultTextStyle.
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: Theme.of(context).textTheme.bodyMedium?.color,
            ),
          ),
        ],
      ),
    );
  }

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
        total += _kPageNavWidth;
      } else if (w is PopupMenuButton) {
        total += 48;
      } else if (w is ConstrainedBox) {
        // v9-D2: the items-per-page chip has a fixed width; estimate it as such.
        total += _kPerPageTextWidth;
      } else if (w is InkWell) {
        total += _kPerPageTextWidth;
      } else {
        total += _kSelectedCountWidth;
      }
      total += _kSpacing;
    }
    return total;
  }

  void _handleNumericJump(BuildContext context) {
    final t = getLocalizations(context);
    final int totalPages = dataSource.totalPages;
    showKeyboardTextPrompt(
      context: context,
      title: t.browser_jump_title,
      label: t.browser_jump_label,
      hint: t.browser_jump_hint(totalPages),
      confirmLabel: t.browser_jump_go,
      cancelLabel: t.cancel,
      keyboardType: TextInputType.number,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.digitsOnly,
      ],
      validate: (value) {
        final target = int.tryParse(value);
        if (target == null || target < 1 || target > totalPages) {
          return t.browser_jump_invalid;
        }
        return null;
      },
    ).then((value) {
      if (value == null) return;
      final target = int.tryParse(value);
      if (target == null) return;
      dataSource.fetchPage(target - 1, dataSource.pageSize);
    });
  }

  void _handleChangePageSize(BuildContext context) {
    final t = getLocalizations(context);
    showKeyboardTextPrompt(
      context: context,
      title: t.browser_size_title,
      label: t.browser_size_label,
      hint: t.browser_size_input_hint,
      helper: t.browser_size_helper(
        t.browser_size_total(dataSource.totalItems),
        t.browser_size_hint,
      ),
      initialValue: '${dataSource.pageSize}',
      confirmLabel: t.browser_size_apply,
      cancelLabel: t.cancel,
      keyboardType: TextInputType.number,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.digitsOnly,
      ],
      validate: (value) {
        final target = int.tryParse(value);
        if (target == null || target < 1 || target > 100000) {
          return t.browser_size_invalid;
        }
        return null;
      },
    ).then((value) {
      if (value == null) return;
      final target = int.tryParse(value);
      if (target == null) return;
      dataSource.changePageSize(target);
    });
  }
}
