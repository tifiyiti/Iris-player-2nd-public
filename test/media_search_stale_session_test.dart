import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/enum/media_lib_sources.dart';
import 'package:iris/features/media_library/search/data_source/media_search_data_source.dart';
import 'package:iris/features/media_library/search/model/search_context.dart';
import 'package:iris/features/media_library/search/model/search_scope.dart';
import 'package:iris/features/media_library/search/store/search_browser_store.dart';
import 'package:iris/features/media_library/search/store/use_media_lib_search_store.dart';
import 'package:iris/features/media_library/search/view/media_search_page.dart';
import 'package:iris/features/media_library/store/browser_open_mode.dart';
import 'package:iris/features/media_library/store/use_media_lib_browser_store.dart';
import 'package:iris/features/media_library/view/content/store/use_media_lib_content_store.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';
import 'package:iris/features/scenario_playback/view/coordinator/scenario_browser_store.dart';
import 'package:iris/features/scenario_playback/view/sources/paged_scenario_sources_data_source.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/widgets/popup.dart';
import 'package:provider/provider.dart';
import 'package:zustand/zustand.dart';

/// StoreScope-equivalent for widget tests that must NOT dispose the global
/// StoreLocator on unmount (see media_search_session_test.dart for the reason).
Widget searchProviderScope(Widget child) {
  return InheritedProvider<StoreLocator>.value(
    value: StoreLocator(),
    startListening: (InheritedContext<StoreLocator?> e, StoreLocator value) {
      final sub = value.changes.listen((_) => e.markNeedsNotifyDependents());
      return sub.cancel;
    },
    lazy: false,
    child: child,
  );
}

/// Stale-session degradation (v6-D1…D5): a scenario-bound parked search session
/// whose SystemPlaying workspace was overridden since creation is NOT resumed —
/// reopening the storagedb degrades to the SystemPlaying scenario sources page
/// showing the CURRENT explicit items. Media-library (C) sessions are never
/// stale; unchanged scenario sessions resume normally.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final db = AppDatabase(NativeDatabase.memory());
    DbModule.init(db);
    useMediaLibSearchStore();
    useMediaLibContentStore();
    await useMediaLibSearchStore().initialized;
    await useMediaLibContentStore().initialized;
    usePlaybackScenarioStore();
    await usePlaybackScenarioStore().initialized;
  });

  setUp(() {
    useSearchBrowserStore().destroySession();
    useSearchBrowserStore().clearAll();
    useSearchBrowserStore().setPinned(false);
    useMediaLibBrowserStore().closeBrowser();
    useScenarioBrowserStore().setMode(ScenarioBrowserMode.queue);
  });

  SearchContext scenarioContext(String scenarioId) => SearchContext(
        entryContext: SearchEntryContext.scenarioSourcesRoot,
        scenarioId: scenarioId,
        sources: const [],
        explicitItems: const [],
      );

  SearchContext libContext() => const SearchContext(
        entryContext: SearchEntryContext.libPathTreeDir,
        storageId: 's',
        parentPath: 'a',
        sources: [
          SearchSource(
            storageId: 's',
            path: 'a',
            kind: MediaSourceKind.directory,
            recursive: true,
          ),
        ],
      );

  group('takeParkedSession stale branch (v6-D3)', () {
    test('an unchanged scenario session resumes with the "was parked" marker', () {
      final ds = MediaSearchDataSource(searchContext: scenarioContext('sc1'));
      useSearchBrowserStore().parkSession(ds);
      expect(useSearchBrowserStore().parkedSearchSession, same(ds));

      final resumed = useSearchBrowserStore().takeParkedSession();
      expect(resumed, same(ds));
      expect(useSearchBrowserStore().consumeWasParked(), isTrue);
      expect(useSearchBrowserStore().consumeParkedStale(), isFalse);
      ds.dispose();
    });

    test('an overridden scenario session is discarded as stale', () {
      final store = usePlaybackScenarioStore();
      final ds = MediaSearchDataSource(searchContext: scenarioContext('sc1'));
      useSearchBrowserStore().parkSession(ds);
      store.bumpWorkspaceOverrideRevision();

      final resumed = useSearchBrowserStore().takeParkedSession();
      expect(resumed, isNull);
      expect(useSearchBrowserStore().parkedSearchSession, isNull);
      expect(useSearchBrowserStore().consumeParkedStale(), isTrue);
      // The "was parked" marker must NOT be set — the next open is a fresh
      // search that must run its initial fetch.
      expect(useSearchBrowserStore().consumeWasParked(), isFalse);
      // One-shot marker is consumed.
      expect(useSearchBrowserStore().consumeParkedStale(), isFalse);
    });
  });

  group('isStaleByWorkspaceOverride (v6-D2)', () {
    test('media-library (C) sessions are never stale', () {
      final store = usePlaybackScenarioStore();
      final ds = MediaSearchDataSource(searchContext: libContext());
      expect(ds.isStaleByWorkspaceOverride, isFalse);
      store.bumpWorkspaceOverrideRevision();
      expect(ds.isStaleByWorkspaceOverride, isFalse);
      ds.dispose();
    });

    test('user-scenario (B) sessions become stale after an override', () {
      final store = usePlaybackScenarioStore();
      final ds = MediaSearchDataSource(searchContext: scenarioContext('sc1'));
      expect(ds.isStaleByWorkspaceOverride, isFalse);
      store.bumpWorkspaceOverrideRevision();
      expect(ds.isStaleByWorkspaceOverride, isTrue);
      ds.dispose();
    });

    test('system-playing (A) sessions become stale after an override', () async {
      final store = usePlaybackScenarioStore();
      final sys = await store.ensureSystemPlayingScenario();
      await store.refreshScenarios();
      final ds = MediaSearchDataSource(searchContext: scenarioContext(sys.id));
      expect(ds.isStaleByWorkspaceOverride, isFalse);
      store.bumpWorkspaceOverrideRevision();
      expect(ds.isStaleByWorkspaceOverride, isTrue);
      ds.dispose();
    });
  });

  group('page degradation on reopen (v6-D4/D5)', () {
    testWidgets('a stale scenario session degrades to the SystemPlaying sources page',
        (tester) async {
      final store = usePlaybackScenarioStore();
      final sys = await store.ensureSystemPlayingScenario();
      await store.refreshScenarios();

      final context = scenarioContext(sys.id);
      useSearchBrowserStore().setScenarioSourcesEntry(
        context: context,
        returnPage: 2,
        groupOrder: const <ScenarioManageGroup>[],
        hiddenGroups: const <ScenarioManageGroup>{},
      );
      final ds = MediaSearchDataSource(searchContext: context);
      useSearchBrowserStore().parkSession(ds);
      store.bumpWorkspaceOverrideRevision();

      await tester.pumpWidget(searchProviderScope(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Material(
            color: Colors.transparent,
            child: MediaSearchPage(direction: PopupDirection.right),
          ),
        ),
      ));
      // Deferred l10n delegates load async — settle so the page mounts.
      await tester.pumpAndSettle();

      // The stale session is discarded; the page degrades to the SystemPlaying
      // scenario manager (sources mode) showing the current explicit items.
      expect(useSearchBrowserStore().parkedSearchSession, isNull);
      expect(useSearchBrowserStore().searchContext, isNull);
      expect(useScenarioBrowserStore().state.mode, ScenarioBrowserMode.sources);
      expect(usePlaybackScenarioStore().state.activeScenarioId, sys.id);
      expect(useMediaLibBrowserStore().state.openMode, BrowserOpenMode.scenario);
      // The one-shot stale marker was consumed by the navigation effect.
      expect(useSearchBrowserStore().consumeParkedStale(), isFalse);
    });

    testWidgets('an unchanged scenario session resumes (no degradation)',
        (tester) async {
      final context = scenarioContext('sc1');
      useSearchBrowserStore().setScenarioSourcesEntry(
        context: context,
        returnPage: 1,
        groupOrder: const <ScenarioManageGroup>[],
        hiddenGroups: const <ScenarioManageGroup>{},
      );
      final ds = MediaSearchDataSource(searchContext: context);
      useSearchBrowserStore().parkSession(ds);

      await tester.pumpWidget(searchProviderScope(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Material(
            color: Colors.transparent,
            child: MediaSearchPage(direction: PopupDirection.right),
          ),
        ),
      ));
      // Deferred l10n delegates load async — settle so the page mounts.
      await tester.pumpAndSettle();

      // The search page resumes and the parked session was taken, not stale.
      expect(find.byType(MediaSearchPage), findsOneWidget);
      expect(useSearchBrowserStore().parkedSearchSession, isNull);
      expect(useSearchBrowserStore().consumeParkedStale(), isFalse);
      // Seeds are kept for the eventual Back restore.
      expect(useSearchBrowserStore().searchContext, isNotNull);
    });

    testWidgets('a media-library (C) session resumes even after an override',
        (tester) async {
      final store = usePlaybackScenarioStore();
      final context = libContext();
      useSearchBrowserStore().setMediaLibEntry(context);
      final ds = MediaSearchDataSource(searchContext: context);
      useSearchBrowserStore().parkSession(ds);
      store.bumpWorkspaceOverrideRevision();

      await tester.pumpWidget(searchProviderScope(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Material(
            color: Colors.transparent,
            child: MediaSearchPage(direction: PopupDirection.right),
          ),
        ),
      ));
      // Deferred l10n delegates load async — settle so the page mounts.
      await tester.pumpAndSettle();

      expect(find.byType(MediaSearchPage), findsOneWidget);
      expect(useSearchBrowserStore().parkedSearchSession, isNull);
      expect(useSearchBrowserStore().consumeParkedStale(), isFalse);
    });
  });
}
