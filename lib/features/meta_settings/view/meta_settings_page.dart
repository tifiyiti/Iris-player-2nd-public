import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/meta_settings/contributions/settings_catalog.dart';
import 'package:iris/features/meta_settings/engine/def_visibility.dart';
import 'package:iris/features/meta_settings/model/enum/settings_section.dart';
import 'package:iris/features/meta_settings/model/setting_def.dart';
import 'package:iris/features/meta_settings/view/setting_texts.dart';
import 'package:iris/features/meta_settings/view/widgets/setting_row.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/popups/settings/about.dart';
import 'package:iris/widgets/popups/settings/dependencies.dart';

/// Metadata-driven settings page — the "written once" renderer.
///
/// Play/General render from contribution defs; About/Dependencies reuse the
/// legacy widgets verbatim (static content, no value semantics).
///
/// PERFORMANCE (phone-relevant):
///  - the page subscribes only to the gate flags `DefVisibility` rules
///    consult, NOT the whole [AppState];
///  - each section is a lazy `ListView.builder`, so off-screen rows are never
///    constructed (a 60-row page no longer builds every tile on open);
///  - generic rows resolve their OWN field via a per-state cached JSON view
///    (SettingRow), so one toggle does not serialize/rebuild the whole page.
class MetaSettingsPage extends HookWidget {
  const MetaSettingsPage({super.key});

  /// All defs merged + validated once; contributions are const data.
  static final List<SettingDef> _defs = SettingsCatalog.defs;

  static String _platformName(TargetPlatform p) => switch (p) {
        TargetPlatform.android => 'android',
        TargetPlatform.iOS => 'ios',
        TargetPlatform.windows => 'windows',
        TargetPlatform.linux => 'linux',
        TargetPlatform.macOS => 'macos',
        _ => '',
      };

  static bool visibleOnCurrentPlatform(SettingDef def) {
    if (def.platforms.isEmpty) return true;
    final name = _platformName(defaultTargetPlatform);
    return def.platforms.contains(name);
  }

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    // Rebuild only when a flag a DefVisibility rule reads changes. (Feature
    // stores that gate a row — e.g. the 副音 scope mode — already behaved this
    // way before: their changes never rebuilt this page either.)
    useAppStore().select(
        context,
        (s) => (
              s.useMetadataSettings,
              s.useLegacyStoragePersistence,
              s.useScenarioDrivenPlayback,
              s.desktopCenterZonePhoneMode,
            ));

    final tabs = <ITab>[
      ITab(
          title: t.play,
          child: const _SettingsSectionList(section: SettingsSection.play)),
      ITab(
          title: t.general,
          child: const _SettingsSectionList(section: SettingsSection.general)),
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
                // Flexible so four scrollable tabs + close button fit
                // constrained panels (phone landscape) without overflow.
                Flexible(
                  child: TabBar(
                      controller: tabController,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      dividerColor: Colors.transparent,
                      tabs: tabs.map((e) => Tab(text: e.title)).toList()),
                ),
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

class ITab {
  final String title;
  final Widget child;

  const ITab({
    required this.title,
    required this.child,
  });
}

/// Lazy section renderer: builds a lightweight entry list (headers + rows)
/// once per build, then materializes only the visible entries.
class _SettingsSectionList extends StatelessWidget {
  const _SettingsSectionList({required this.section});

  final SettingsSection section;

  List<_SectionEntry> _entries(AppLocalizations t) {
    final entries = <_SectionEntry>[];
    for (final d in MetaSettingsPage._defs) {
      if (d.section != section) continue;
      if (!MetaSettingsPage.visibleOnCurrentPlatform(d)) continue;
      // Unavailable features are never displayed (e.g. tag_play while the
      // metadata gate is OFF).
      if (!DefVisibility.isVisible(d.key)) continue;
      if (d.groupHeaderKey != null) {
        entries.add(_SectionHeader(
          text: SettingTexts.groupLabel(d.groupHeaderKey!, t),
          showDivider: entries.isNotEmpty,
        ));
      }
      entries.add(_SectionRow(d));
    }
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries(getLocalizations(context));
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final e = entries[index];
        if (e is _SectionHeader) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (e.showDivider) const Divider(height: 1),
              _GroupHeader(text: e.text),
            ],
          );
        }
        final def = (e as _SectionRow).def;
        return SettingRow(key: ValueKey(def.key), def: def);
      },
    );
  }
}

sealed class _SectionEntry {
  const _SectionEntry();
}

class _SectionHeader extends _SectionEntry {
  const _SectionHeader({required this.text, required this.showDivider});

  final String text;
  final bool showDivider;
}

class _SectionRow extends _SectionEntry {
  const _SectionRow(this.def);

  final SettingDef def;
}

/// Section header introducing a new visual group (divider rendered by the
/// list assembly when it is not the first group).
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}
