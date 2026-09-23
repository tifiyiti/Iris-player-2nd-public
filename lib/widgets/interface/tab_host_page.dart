import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/a11y_tooltip.dart';
import 'package:iris/widgets/interface/tab_page_module.dart';

class TabHostPage<T extends TabPageModule> extends HookWidget {
  /// List of tabs to show
  final List<T> tabs;

  final bool showTabs;

  final int initialIndex;

  /// Called with the settled tab index whenever the user switches tabs, so
  /// callers can persist the active tab for the next reopen.
  final ValueChanged<int>? onTabChanged;

  const TabHostPage({
    super.key,
    required this.tabs,
    this.showTabs = true,
    this.initialIndex = 0,
    this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (tabs.isEmpty) {
      return Center(child: Text(getLocalizations(context).browser_no_tabs));
    }

    if (!showTabs || tabs.length == 1) {
      return tabs.first.buildPage(context);
    }

    final tabController = useTabController(initialLength: tabs.length, initialIndex: initialIndex);

    useEffect(() {
      void onChanged() {
        if (tabController.indexIsChanging) return;
        onTabChanged?.call(tabController.index);
      }

      tabController.addListener(onChanged);
      return () => tabController.removeListener(onChanged);
    }, [tabController, onTabChanged]);

    return Column(
      children: [
        Expanded(
          child: TabBarView(
            controller: tabController,
            children: tabs.map((tab) => _wrapTabCard(tab.buildPage(context))).toList(),
          ),
        ),
        _buildDivider(context),
        _buildBottomBar(context, tabController, tabs),
      ],
    );
  }

  Widget _wrapTabCard(Widget child) => Card(
        color: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: child,
      );

  Widget _buildDivider(BuildContext context) => Divider(
        color: Theme.of(context).colorScheme.primary.withAlpha(64),
        height: 0,
      );

  Widget _buildBottomBar(BuildContext context, TabController controller, List<T> tabs) {
    return AnimatedBuilder(
      animation: controller.animation!,
      builder: (context, child) {
        final currentIndex = controller.animation!.value.round().clamp(0, tabs.length - 1);

        return Container(
          padding: const EdgeInsets.fromLTRB(0, 0, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: controller,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  dividerColor: Colors.transparent,
                  tabs: tabs.map((tab) => Tab(text: tab.title(context))).toList(),
                ),
              ),
              if (tabs[currentIndex].buildAction(context) != null)
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  child: tabs[currentIndex].buildAction(context) ?? const SizedBox.shrink(),
                ),
              a11yTooltipIconButton(
                context: context,
                tooltip: '${getLocalizations(context).close} (Escape)',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      },
    );
  }
}
