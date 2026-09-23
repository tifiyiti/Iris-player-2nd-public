import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/media_library/search/view/media_search_page.dart';
import 'package:iris/features/media_library/store/browser_open_mode.dart';
import 'package:iris/features/media_library/store/use_media_lib_browser_store.dart';
import 'package:iris/features/media_library/view/content/pages/media_lib_content_page.dart';
import 'package:iris/features/media_library/view/tab/media_lib_tab_page.dart';
import 'package:iris/features/media_library/view/tab/widget/generic_browser_router_entry.dart';
import 'package:iris/features/scenario_playback/view/coordinator/scenario_browser.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_storage_store.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/widgets/interface/tab_host_page.dart';
import 'package:iris/widgets/interface/tab_page_module.dart';
import 'package:iris/features/media_library/view/files_db_paging/files_db_use_paginated_browser.dart';
import 'package:iris/widgets/popups/storages/db/tabs/favorites_tab_page.dart';
import 'package:iris/widgets/popups/storages/db/tabs/playback_scenario_tab_page.dart';
import 'package:iris/widgets/popups/storages/db/tabs/storage_tab_page.dart';
import 'package:iris/widgets/popups/storages/files.dart';
final areaKeyLog = AreaKeyLog(LogKeys.legacyUi);

class StoragesDb extends HookWidget {
  const StoragesDb({super.key});

  @override
  Widget build(BuildContext context) {
    //final t = getLocalizations(context);

    final storageStore = useStorageStore();
    final currentStorage =
        storageStore.select(context, (s) => s.currentStorage);

    final useLegacy =
        useAppStore().select(context, (s) => s.useLegacyStoragePersistence);

    final browserStore = useMediaLibBrowserStore();
    final openMode = browserStore.select(context, (s) => s.openMode);
    final lastActiveTab = browserStore.select(context, (s) => s.lastActiveTab);

    final currentPath = storageStore.select(context, (s) => s.currentPath);

    // ensure currentPath is restored after store loads
    useEffect(() {
      if (storageStore.loaded &&
          currentStorage != null &&
          currentPath.isEmpty) {
        storageStore.updateCurrentPath(currentStorage.basePath);
      }
      return null;
    }, [storageStore.loaded, currentStorage, currentPath]);

    // Track lastActiveTab for correct tab on return
    useEffect(() {
      if (currentStorage != null) {
        browserStore.setLastActiveTab(0);
      }
      return null;
    }, [currentStorage]);

    useEffect(() {
      if (openMode == BrowserOpenMode.mock ||
          openMode == BrowserOpenMode.libContent) {
        browserStore.setLastActiveTab(2);
      }
      return null;
    }, [openMode]);

    // wait for persistence initialization
    if (!storageStore.loaded) {
      areaKeyLog.i('Waiting for store initialization...');
      return const Center(child: CircularProgressIndicator());
    }

    // Storage file browser
    if (currentStorage != null) {
      return useLegacy
          ? Files(storage: currentStorage)
          : FilesDbUsePaginatedBrowser(
              storage: currentStorage,
              onBack: () {
                storageStore.updateCurrentStorage(null);
                storageStore.updateCurrentPath([]);
              },
              onClose: () => Navigator.of(context).pop(),
            );
    }

    // Media library browser (mock for now)
    if (openMode == BrowserOpenMode.mock) {
      return GenericBrowserRouterEntry(
        onBack: () => browserStore.closeBrowser(),
        onClose: () => Navigator.of(context).pop(),
      );
    }

    // Media library content browser
    if (openMode == BrowserOpenMode.libContent) {
      return MediaLibContentPage(
        onBack: () => browserStore.closeBrowser(),
        onClose: () => Navigator.of(context).pop(),
      );
    }

    // Scenario manager sub-interface (same mechanism as libContent: back/home
    // closes the sub-interface and returns to the tabs at the scenario tab).
    if (openMode == BrowserOpenMode.scenario) {
      final direction =
          useAppStore().select(context, (s) => s.defaultPopupDirection);
      return ScenarioBrowser(
        direction: direction,
        embeddedInStoragesDb: true,
      );
    }

    // Independent media search page (media-library entry, F-001/F-003).
    if (openMode == BrowserOpenMode.search) {
      final direction =
          useAppStore().select(context, (s) => s.defaultPopupDirection);
      return MediaSearchPage(
        direction: direction,
        embeddedInStoragesDb: true,
      );
    }

    // Default: show tabs with the correct active tab
    final List<TabPageModule> tabs = [
      StorageTabPage(),
      PlaybackScenarioTabPage(),
      MediaLibTabPage(),
      FavoritesTabPage(),
    ];

    return TabHostPage(
      tabs: tabs,
      showTabs: true,
      initialIndex: lastActiveTab,
      onTabChanged: browserStore.setLastActiveTab,
    );
  }
}
