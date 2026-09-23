import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/enum/media_lib_sources.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
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
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/widgets/popup.dart';
import 'package:provider/provider.dart';
import 'package:zustand/zustand.dart';

/// StoreScope-equivalent for widget tests that must NOT dispose the global
/// StoreLocator on unmount. [StoreScope] (flutter_zustand) calls
/// `StoreLocator().dispose()` fire-and-forget in its State.dispose; the
/// singleton teardown races the next testWidgets' stores against a closing
/// locator ("Cannot add new events after calling close"). This wrapper keeps
/// the singleton alive across tests — mirroring StoreScope's build (provider +
/// change-listening for `select(context, ...)`) minus the dispose.
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

/// Search session lifecycle (v11-D4 / v12-D1): Close parks the page (state +
/// page survive reopen), Back AND Home destroy it (fresh page next time); pin
/// is in-memory and resets on destroy.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final db = AppDatabase(NativeDatabase.memory());
    DbModule.init(db);
    useMediaLibSearchStore();
    useMediaLibContentStore();
    await useMediaLibSearchStore().initialized;
    await useMediaLibContentStore().initialized;
  });

  setUp(() {
    useSearchBrowserStore().destroySession();
    useSearchBrowserStore().clearAll();
    useSearchBrowserStore().setPinned(false);
  });

  Future<void> seedFile(String storageId, String p) async {
    await DbModule.mediaNodesDao.deleteNode(storageId, p);
    final segments = p.split('/');
    await DbModule.mediaNodesDao.insertNode(MediaNode.file(
      id: 'f:$storageId:$p',
      storageId: storageId,
      path: segments,
      name: segments.last,
      mediaType: MediaType.video,
    ));
  }

  MediaSearchDataSource libDataSource() => MediaSearchDataSource(
        searchContext: const SearchContext(
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
        ),
      );

  group('SearchBrowserStore session primitives (v11-D4)', () {
    test('park → take returns the same instance and marks resumed', () {
      final ds = libDataSource();
      useSearchBrowserStore().parkSession(ds);
      expect(useSearchBrowserStore().parkedSearchSession, same(ds));

      final resumed = useSearchBrowserStore().takeParkedSession();
      expect(resumed, same(ds));
      expect(useSearchBrowserStore().consumeWasParked(), isTrue);
      // A second consume reports false (one-shot).
      expect(useSearchBrowserStore().consumeWasParked(), isFalse);
      ds.dispose();
    });

    test('clearAll does not clear the parked session or the pin', () {
      final ds = libDataSource();
      useSearchBrowserStore().parkSession(ds);
      useSearchBrowserStore().setPinned(true);
      useSearchBrowserStore().clearAll();
      expect(useSearchBrowserStore().parkedSearchSession, same(ds));
      expect(useSearchBrowserStore().pinned, isTrue);
      ds.dispose();
    });

    test('destroySession disposes the session, clears it and resets the pin',
        () {
      final ds = libDataSource();
      useSearchBrowserStore().parkSession(ds);
      useSearchBrowserStore().setPinned(true);
      useSearchBrowserStore().destroySession();
      expect(useSearchBrowserStore().parkedSearchSession, isNull);
      expect(useSearchBrowserStore().pinned, isFalse);
      // Double-destroy is safe (data source guards dispose).
      useSearchBrowserStore().destroySession();
    });
  });

  group('resume preserves the query + page (v11-D4)', () {
    test('a parked session resumes with its items and page', () async {
      await seedFile('s', 'a/movie1.mp4');
      await seedFile('s', 'a/movie2.mp4');
      final ds = libDataSource();

      // Plain test runs in the real zone, so drift queries complete directly.
      await ds.submitQuery('movie');

      expect(ds.items, isNotEmpty);
      expect(ds.currentPage, 0);
      expect(ds.query, 'movie');

      useSearchBrowserStore().parkSession(ds);
      final resumed = useSearchBrowserStore().takeParkedSession();
      expect(resumed, same(ds));
      // The resumed session keeps its loaded page — no initial fetch needed.
      expect(resumed!.items, isNotEmpty);
      expect(resumed.currentPage, 0);
      expect(resumed.query, 'movie');
      resumed.dispose();
    });
  });

  group('Close parks + closes the popup (v11-D4 / v13-D1)', () {
    testWidgets('tapping Close parks the session and pops the whole popup',
        (tester) async {
      useSearchBrowserStore().setMediaLibEntry(
        const SearchContext(
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
        ),
      );

      // handleClose now calls Navigator.pop() — the search page must live in a
      // pushed route, not the app's root (popping the root would fail). The
      // provider scope keeps the global StoreLocator alive across tests.
      await tester.pumpWidget(searchProviderScope(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    Popup(
                      direction: PopupDirection.right,
                      child: const MediaSearchPage(
                          direction: PopupDirection.right),
                    ),
                  ),
                  child: const Text('open search'),
                ),
              ),
            ),
          ),
        ),
      ));
      // Deferred l10n delegates load async — settle so the page mounts.
      await tester.pumpAndSettle();
      await tester.tap(find.text('open search'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // popup entrance
      expect(find.byType(MediaSearchPage), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pump();
      // The session is parked for a later resume…
      expect(useSearchBrowserStore().parkedSearchSession, isNotNull);
      // Scenario return seeds stay for the entry page to consume on reopen.
      expect(useSearchBrowserStore().scenarioSearchReturnMode, isNull);
      // …and the whole popup route was closed.
      await tester.pump(const Duration(milliseconds: 300)); // popup exit
      expect(find.byType(MediaSearchPage), findsNothing);
    });
  });

  group('Back destroys the page (v11-D4 / v12-D1)', () {
    testWidgets('tapping Back destroys the session for a fresh page',
        (tester) async {
      useSearchBrowserStore().setMediaLibEntry(
        const SearchContext(
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
        ),
      );

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
      await tester.tap(find.byTooltip('Back'));
      await tester.pump();

      // Back destroys: nothing parked, pin reset, interface restored to the
      // media-library content page.
      expect(useSearchBrowserStore().parkedSearchSession, isNull);
      expect(useSearchBrowserStore().pinned, isFalse);
      expect(useMediaLibBrowserStore().state.openMode,
          BrowserOpenMode.libContent);
    });
  });

  group('Home destroys the page (v12-D1)', () {
    testWidgets('tapping Home clears the session and lands on the tabs root',
        (tester) async {
      useSearchBrowserStore().setMediaLibEntry(
        const SearchContext(
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
        ),
      );
      // Park a live session first — Home must destroy (not resume) it.
      final ds = libDataSource();
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

      // The parked session was resumed by the page mount.
      expect(useSearchBrowserStore().parkedSearchSession, isNull);

      await tester.tap(find.byTooltip('Home'));
      await tester.pump();

      // Home destroys: nothing parked, seeds cleared, pin reset, tabs root.
      expect(useSearchBrowserStore().parkedSearchSession, isNull);
      expect(useSearchBrowserStore().searchContext, isNull);
      expect(useSearchBrowserStore().pinned, isFalse);
      expect(useMediaLibBrowserStore().state.openMode, BrowserOpenMode.tabs);
      ds.dispose();
    });
  });
}
