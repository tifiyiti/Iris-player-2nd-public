import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/meta_settings/view/meta_settings_page.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/popups/settings/about.dart';
import 'package:iris/widgets/popups/settings/dependencies.dart';
import 'package:iris/widgets/popups/settings/general.dart';
import 'package:iris/widgets/popups/settings/play.dart';

class ITab {
  final String title;
  final Widget child;

  const ITab({
    required this.title,
    required this.child,
  });
}

class Settings extends HookWidget {
  const Settings({super.key});

  static const title = 'Settings';

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);

    // Metadata-settings gate: ON → the DB-backed renderer replaces the whole
    // legacy panel (it owns its own tab bar + close button). OFF → untouched
    // legacy path, byte-for-byte.
    final useMeta =
        useAppStore().select(context, (s) => s.useMetadataSettings);
    if (useMeta) return const MetaSettingsPage();

    // Play is the primary user workflow, so it is placed first to be the default tab.
    // the most frequent interaction rather than general configuration.
    List<ITab> tabs = [
      ITab(title: t.play, child: const Play()),
      ITab(title: t.general, child: const General()),
      ITab(title: t.about, child: const About()),
      ITab(title: t.dependencies, child: const Dependencies()),
    ];

    final tabController = useTabController(initialLength: tabs.length);

    return Column(
      children: [
        Expanded(
          child: TabBarView(
            controller: tabController,
            children: tabs
                .map((e) => Card(
                      color: Colors.transparent,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: e.child,
                    ))
                .toList(),
          ),
        ),
        Divider(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
          height: 0,
        ),
        Container(
          padding: EdgeInsets.zero,
          child: Container(
            padding: const EdgeInsets.fromLTRB(0, 0, 4, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                TabBar(
                    controller: tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    dividerColor: Colors.transparent,
                    tabs: tabs.map((e) => Tab(text: e.title)).toList()),
                const Spacer(),
                IconButton(
                  tooltip: '${t.close} ( Escape )',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
