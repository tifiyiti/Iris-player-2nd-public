import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/meta_settings/meta_settings_module.dart';
import 'package:iris/features/paginated_browser/paginated_browser_page.dart';
import 'package:iris/features/scenario_playback/view/coordinator/scenario_browser.dart';
import 'package:iris/features/scenario_playback/view/coordinator/scenario_browser_store.dart';
import 'package:iris/features/scenario_playback/view/sources/paged_scenario_preview_data_source.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/widgets/popup.dart';

/// Preview (temporary) sub-interface of the scenario browser.
///
/// Renders the read-only resolved queue of
/// [ScenarioBrowserStore.previewScenarioId], generated fresh from scenario
/// data via [PlaybackScenarioStore.resolvePageFor] each time it is opened.
/// Nothing is persisted: back restores the interface the preview was opened
/// from ([ScenarioBrowserStore.previewReturnMode]); home/X return to the
/// Playback Scenario tab.
class ScenarioPreviewPage extends HookWidget {
  final PopupDirection direction;
  final void Function(BuildContext context)? onExit;
  final bool embeddedInStoragesDb;

  /// True when this page belongs to a `modeQueueOverride` browser (floating
  /// queue popup / docked panel). Never read the global
  /// [ScenarioBrowserStore.queueOverrideActive] here: a concurrently-mounted
  /// dock would otherwise hijack the embedded storagedb manager's routing.
  final bool queueOverride;

  const ScenarioPreviewPage({
    super.key,
    required this.direction,
    this.onExit,
    this.embeddedInStoragesDb = false,
    this.queueOverride = false,
  });

  @override
  Widget build(BuildContext context) {
    final scenarioId = useScenarioBrowserStore().previewScenarioId ?? '';

    final dataSource = useMemoized(
      () => PagedScenarioPreviewDataSource(
        scenarioId: scenarioId,
        onExitPreview: () => _exitPreview(context),
      ),
      [scenarioId, embeddedInStoragesDb],
    );
    useEffect(() => () => dataSource.dispose(), [dataSource]);

    if (scenarioId.isEmpty) {
      return const SizedBox.shrink();
    }

    // Playlist keyboard model (PotPlayer PL) is metadata-era only.
    final listKeyboard = useAppStore().select(
          context,
          (s) => s.useMetadataSettings,
        ) &&
        MetaSettingsModule.ready;

    return PaginatedBrowserPage(
      dataSource: dataSource,
      onHomePage: () => goToScenarioTab(context, direction,
          embedded: embeddedInStoragesDb, queueOverride: queueOverride),
      onClose: () => _close(context),
      showHomePage: true,
      showBackButton: true,
      listKeyboard: listKeyboard,
    );
  }

  /// Exits preview back to the interface it was opened from (restores the
  /// recorded [ScenarioBrowserStore.previewReturnMode]), else the storagedb tabs.
  /// Queue-owned preview uses queueOverrideMode, storagedb uses persisted mode.
  void _exitPreview(BuildContext context) {
    final b = useScenarioBrowserStore();
    final returnMode = b.previewReturnMode;
    if (returnMode != null) {
      if (queueOverride) {
        b.setQueueOverrideMode(returnMode);
      } else {
        b.setMode(returnMode);
      }
      return;
    }
    if (queueOverride) {
      // Preview from queue Manage (returnMode null): back to Sources root.
      b.setQueueOverrideMode(ScenarioBrowserMode.sources);
      return;
    }
    goToScenarioTab(context, direction,
        embedded: embeddedInStoragesDb, queueOverride: queueOverride);
  }

  void _close(BuildContext context) {
    final exit = onExit;
    if (exit != null) {
      exit(context);
      return;
    }
    if (queueOverride) {
      // X closes the whole queue popup/panel (spec: X always closes popup).
      Navigator.of(context).pop();
      return;
    }
    goToScenarioTab(context, direction,
        embedded: embeddedInStoragesDb, queueOverride: queueOverride);
  }
}
