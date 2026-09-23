import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/media_library/store/browser_open_mode.dart';
import 'package:iris/features/media_library/store/media_lib_browser_state.dart';

class MediaLibBrowserStore extends Store<MediaLibBrowserState> {
  MediaLibBrowserStore() : super(const MediaLibBrowserState());

  void openStorage() => set(state.copyWith(
        openMode: BrowserOpenMode.storageFiles,
        lastActiveTab: 0,
      ));

  void openMock() => set(state.copyWith(
        openMode: BrowserOpenMode.mock,
        lastActiveTab: 2,
      ));

  void openLibContent() => set(state.copyWith(
        openMode: BrowserOpenMode.libContent,
        lastActiveTab: 2,
      ));

  /// Opens the scenario manager as a full-page sub-interface of [StoragesDb]
  /// (same mechanism as [openLibContent]), landing on the Playback Scenario tab
  /// when closed.
  void openScenario() => set(state.copyWith(
        openMode: BrowserOpenMode.scenario,
        lastActiveTab: 1,
      ));

  /// Closes the scenario sub-interface and returns to the storagedb tabs with
  /// the Playback Scenario tab active.
  void openScenarioTab() => set(state.copyWith(
        openMode: BrowserOpenMode.tabs,
        lastActiveTab: 1,
      ));

  /// Opens the media search page as a full-page sub-interface of [StoragesDb]
  /// (same mechanism as [openLibContent]).
  void openSearch() => set(state.copyWith(
        openMode: BrowserOpenMode.search,
        lastActiveTab: 2,
      ));

  /// Closes the media search page back to the MediaDb tab root.
  void openSearchTab() => set(state.copyWith(
        openMode: BrowserOpenMode.tabs,
        lastActiveTab: 2,
      ));

  /// Exits any secondary interface back to the tab host (keeps lastActiveTab).
  void closeBrowser() => set(state.copyWith(openMode: BrowserOpenMode.tabs));

  void setLastActiveTab(int index) => set(state.copyWith(lastActiveTab: index));
}

MediaLibBrowserStore useMediaLibBrowserStore() => create(() => MediaLibBrowserStore());
