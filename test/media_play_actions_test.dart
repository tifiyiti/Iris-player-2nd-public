import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/db/adapters/media_node_drift_adapter.dart';
import 'package:iris/features/media_library/model/enum/media_lib_sources.dart';
import 'package:iris/features/media_library/model/media_lib/media_library.dart';
import 'package:iris/features/media_library/model/media_lib/media_library_source.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/media_library/selection/selection_controller.dart';
import 'package:iris/features/media_library/selection/selection_state.dart';
import 'package:iris/features/media_library/store/use_media_lib_browser_store.dart';
import 'package:iris/features/media_library/view/content/store/use_media_lib_content_store.dart';
import 'package:iris/features/media_library/view/tab/store/libs/use_media_libs_page_store.dart';
import 'package:iris/features/media_library/view/tab/widget/media_lib_tile.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/store/warning_dialogs.dart';
import 'package:iris/store/use_storage_store.dart';
import 'package:iris/widgets/popups/storages/db/storages_db_list.dart';
import 'package:provider/provider.dart';
import 'package:zustand/zustand.dart';

/// F-001: the Storage tab tile's primary trailing button is the whole-storage
/// recursive scan, with Play Override / Play Append / Edit / Remove in the more
/// menu, in scenario mode; legacy mode is untouched.
void main() {
  // StoreScope-equivalent that does NOT dispose the global StoreLocator on
  // unmount (mirrors media_search_session_test.searchProviderScope).
  Widget providerScope(Widget child) {
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
  setUpAll(() async {
    final db = AppDatabase(NativeDatabase.memory());
    DbModule.init(db);
    usePlaybackScenarioStore();
    await usePlaybackScenarioStore().initialized;
    await runZonedGuarded(() async {
      usePlayQueueStore();
      await usePlayQueueStore().initialized;
      useAppStore();
      await useAppStore().initialized;
      // Play actions route through runPlayAction(WithNoMediaConfirm), which
      // shows the first-use workspace notice (kWarningScenarioWorkspace).
      // These tests cover the override install, not the notice, so pre-suppress
      // it as the real second-use onward state does.
      await useAppStore().suppressWarning(kWarningScenarioWorkspace);
      useStorageStore();
      await useStorageStore().initialized;
      useMediaLibsStore();
      await useMediaLibsStore().initialized;
      useMediaLibContentStore();
      useMediaLibBrowserStore();
    }, (Object e, StackTrace st) {});
  });

  setUp(() async {
    final app = useAppStore();
    // Reset legacy flag via `set` — the toggle also switches persistence
    // backends, whose async loads do not complete in the fake-async test zone.
    if (app.state.useLegacyStoragePersistence) {
      app.set(app.state.copyWith(useLegacyStoragePersistence: false));
    }
    final storageStore = useStorageStore();
    for (final s in List.of(storageStore.state.storages)) {
      await storageStore.removeStorage(s);
    }
    await storageStore.addStorage(LocalStorage(
          id: 's',
          type: StorageType.internal,
          name: 'S',
          basePath: ['storage'],
        ));
    final store = usePlaybackScenarioStore();
    final sys = await store.ensureSystemPlayingScenario();
    await store.setActiveScenario(sys.id);
    await store.clearSources(sys.id);
    await store.clearExplicitItems(sys.id);
    await store.clearTemporaryExcludes(sys.id);
    await DbModule.mediaNodesDao.deleteNode('s', 'movie.mp4');
    await DbModule.mediaNodesDao.insertNode(MediaNode.file(
      id: 'f:s:movie.mp4',
      storageId: 's',
      path: const ['movie.mp4'],
      name: 'movie.mp4',
      mediaType: MediaType.video,
    ));
    // Seed the storage root dir node as freshly fully-scanned so the
    // play-time scan gate passes (the tests exercise override INSTALL, not
    // the gate dialog).
    await DbModule.mediaNodesDao.batchUpsert([
      MediaNode.directory(
        id: 'd:s:',
        storageId: 's',
        path: const [],
        parentPath: null,
        pathDepth: 0,
        name: 'S',
      ).toCompanion(),
    ]);
    await DbModule.mediaNodesDao.markDirScanDone('s', '');
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpStoragesDb(WidgetTester tester) async {
    await tester.pumpWidget(providerScope(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: const Scaffold(body: StoragesDbList()),
    )));
    await settle(tester);
  }

  Future<List<String>> workspaceSourcePaths() async {
    final store = usePlaybackScenarioStore();
    final sys = await store.ensureSystemPlayingScenario();
    final sources = await store.getSources(sys.id);
    return sources.map((s) => s.path).toList();
  }

  testWidgets('scenario mode renders the scan primary and Play Override from '
      'the more menu installs the whole-storage override', (tester) async {
    await pumpStoragesDb(tester);
    final tile = find.widgetWithText(ListTile, 'S');
    expect(tile, findsOneWidget);
    // Primary trailing is the recursive scan; the play icon moved into the
    // more menu.
    expect(
        find.descendant(
            of: tile, matching: find.byIcon(Icons.autorenew_rounded)),
        findsOneWidget);
    expect(
        find.descendant(
            of: tile, matching: find.byIcon(Icons.play_arrow_rounded)),
        findsNothing);

    await tester.tap(find.descendant(
        of: tile, matching: find.bySubtype<PopupMenuButton>()));
    await settle(tester);
    await tester.tap(find.text('Play Override'));
    await settle(tester);

    expect(await workspaceSourcePaths(), contains(''));
  });

  testWidgets('scenario scan primary is disabled while the storage is offline',
      (tester) async {
    // Marked offline BEFORE the first build: host-discovered storages may also
    // be listed, so target the renamed 'S (Offline)' tile deterministically.
    useStorageStore().markDisconnected('s');
    addTearDown(() => useStorageStore().markConnected('s'));
    await pumpStoragesDb(tester);

    final tile = find.widgetWithText(ListTile, 'S (Offline)');
    expect(tile, findsOneWidget);
    final scan = find.descendant(
        of: tile, matching: find.byIcon(Icons.autorenew_rounded));
    expect(scan, findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
              find.ancestor(of: scan, matching: find.byType(IconButton)))
          .onPressed,
      isNull,
    );
  });

  testWidgets('more menu contains Play Override / Play Append / Edit / Remove',
      (tester) async {
    await pumpStoragesDb(tester);
    final tile = find.widgetWithText(ListTile, 'S');
    await tester.tap(find.descendant(
        of: tile, matching: find.bySubtype<PopupMenuButton>()));
    await settle(tester);
    expect(find.text('Play Override'), findsOneWidget);
    expect(find.text('Play Append'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);
    // Scan is the primary button now, not a menu entry.
    expect(find.text('Scan recursively'), findsNothing);
  });

  testWidgets('legacy mode does not render Play or scan and keeps Edit/Remove',
      (tester) async {
    useAppStore()
        .set(useAppStore().state.copyWith(useLegacyStoragePersistence: true));
    await pumpStoragesDb(tester);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    expect(find.byIcon(Icons.autorenew_rounded), findsNothing);
    expect(find.bySubtype<PopupMenuButton>(), findsOneWidget);
  });

  // ── F-002 ──

  Future<void> pumpLibTile(
    WidgetTester tester,
    MediaLibrary lib, {
    SelectionController<String>? selection,
  }) async {
    await tester.pumpWidget(providerScope(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: MediaLibTile(
          library: lib,
          selection: selection ??
              SelectionController<String>(
                isSelectable: (_) => true,
                initialState: const SelectionState<String>(),
              ),
          onLongPress: () {},
          onTileTap: (_) {},
        ),
      ),
    )));
    await settle(tester);
  }

  testWidgets('F-002 lib tile Play installs the whole-library override '
      '(dir → source, file → explicit, missing → placeholder)',
      (tester) async {
    await DbModule.mediaNodesDao.deleteNode('s', 'a/movie.mp4');
    await DbModule.mediaNodesDao.insertNode(MediaNode.file(
      id: 'f:s:a/movie.mp4',
      storageId: 's',
      path: const ['a', 'movie.mp4'],
      name: 'movie.mp4',
      mediaType: MediaType.video,
    ));
    // Seed the 'a' dir node as freshly fully-scanned so the play-time scan
    // gate passes (this test exercises the override INSTALL, not the gate).
    await DbModule.mediaNodesDao.batchUpsert([
      MediaNode.directory(
        id: 'd:s:a',
        storageId: 's',
        path: const ['a'],
        parentPath: '',
        pathDepth: 1,
        name: 'a',
      ).toCompanion(),
    ]);
    await DbModule.mediaNodesDao.markDirScanDone('s', 'a');
    await DbModule.sourcesRepository.addSource(MediaLibrarySource(
      id: 1,
      libraryId: 'lib-f002',
      storageId: 's',
      path: const ['a'],
      kind: MediaSourceKind.directory,
    ));
    await DbModule.sourcesRepository.addSource(MediaLibrarySource(
      id: 2,
      libraryId: 'lib-f002',
      storageId: 's',
      path: const ['movie.mp4'],
      kind: MediaSourceKind.file,
    ));
    await DbModule.sourcesRepository.addSource(MediaLibrarySource(
      id: 3,
      libraryId: 'lib-f002',
      storageId: 's',
      path: const ['nope.mp4'],
      kind: MediaSourceKind.file,
    ));

    final lib = MediaLibrary(
      id: 'lib-f002',
      name: 'L',
      type: MediaLibraryType.user,
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );
    await pumpLibTile(tester, lib);

    final tile = find.widgetWithText(ListTile, 'L');
    expect(tile, findsOneWidget);
    final play = find.descendant(
        of: tile, matching: find.byIcon(Icons.play_arrow_rounded));
    expect(play, findsOneWidget);

    await tester.tap(play);
    await settle(tester);

    final store = usePlaybackScenarioStore();
    final sys = await store.ensureSystemPlayingScenario();
    final sources = await store.getSources(sys.id);
    expect(sources.map((s) => s.path), contains('a'));
    final items = await DbModule.scenarioRepo.getExplicitItems(sys.id);
    expect(items.map((e) => e.path), containsAll(['movie.mp4', 'nope.mp4']));
  });

  testWidgets('F-002 lib tile more menu has Play Append + existing entries',
      (tester) async {
    final lib = MediaLibrary(
      id: 'lib-f002b',
      name: 'L2',
      type: MediaLibraryType.user,
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );
    await pumpLibTile(tester, lib);
    final tile = find.widgetWithText(ListTile, 'L2');
    await tester.tap(find.descendant(
        of: tile, matching: find.bySubtype<PopupMenuButton>()));
    await settle(tester);
    expect(find.text('Play Append'), findsOneWidget);
    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Add as Source'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('F-002 legacy mode keeps only the old menu (no Play)',
      (tester) async {
    useAppStore()
        .set(useAppStore().state.copyWith(useLegacyStoragePersistence: true));
    final lib = MediaLibrary(
      id: 'lib-f002c',
      name: 'L3',
      type: MediaLibraryType.user,
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );
    await pumpLibTile(tester, lib);
    final tile = find.widgetWithText(ListTile, 'L3');
    expect(
        find.descendant(
            of: tile, matching: find.byIcon(Icons.play_arrow_rounded)),
        findsNothing);
    await tester.tap(find.descendant(
        of: tile, matching: find.bySubtype<PopupMenuButton>()));
    await settle(tester);
    expect(find.text('Play Append'), findsNothing);
    expect(find.text('Rename'), findsOneWidget);
  });
}
