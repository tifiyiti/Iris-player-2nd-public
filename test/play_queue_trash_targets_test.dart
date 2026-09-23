import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/play_queue/data_source/paged_play_queue_data_source.dart';
import 'package:iris/features/paginated_browser/paginated_browser_controller.dart';
import 'package:iris/features/paginated_browser/paginated_browser_page.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/file.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_history_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:provider/provider.dart';
import 'package:zustand/zustand.dart';

import 'helpers/sqlite3_loader.dart';

/// Queue trash-can delete + the selection-mode Remove (play queue).
///
/// Contract: the trash removes the CURRENT PLAYING row — what the confirm copy
/// promises; selection-mode bulk removal must repaint, not just mutate the
/// store. [resolveTrashTargets] also honours a selection for defence in depth,
/// but that half is unreachable in the current UI (selection mode replaces the
/// bar, so the trash is only ever tappable with an empty selection) and is
/// therefore unit-covered below rather than widget-driven.
FileItem _f(String name) =>
    FileItem(name: name, uri: 'file:///$name', path: [name]);

List<String> _queueNames() =>
    usePlayQueueStore().state.playQueue.map((e) => e.file.name).toList();

/// StoreLocator provider that does NOT dispose the global locator on unmount
/// ([StoreScope] does, fire-and-forget), which would race the next test's
/// first build. Mirrors StoreScope's build minus the dispose — the tiles'
/// `select(context, ...)` needs this above them.
Widget _storeScope(Widget child) {
  return InheritedProvider<StoreLocator>.value(
    value: StoreLocator(),
    startListening: (e, v) {
      final sub = v.changes.listen((_) => e.markNeedsNotifyDependents());
      return sub.cancel;
    },
    lazy: false,
    child: child,
  );
}

Widget _wrap(Widget child) {
  return _storeScope(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(width: 800, height: 600, child: child),
      ),
    ),
  );
}

Widget _page(PaginatedBrowserController<PlayQueueItem> controller) {
  return PaginatedBrowserPage<PlayQueueItem>(
    dataSource: PagedPlayQueueDataSource(),
    controller: controller,
    showHomePage: false,
    showBackButton: false,
  );
}

/// Taps the toolbar trash (`Icons.delete_outline`) and confirms.
Future<void> _confirmTrashDelete(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.delete_outline));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(TextButton, 'Delete'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqlite3Loaded();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  setUpAll(() async {
    await DbModule.init(AppDatabase(NativeDatabase.memory()));
    useAppStore();
    await useAppStore().initialized;
    useHistoryStore();
    await useHistoryStore().initialized;
    usePlayQueueStore();
    await usePlayQueueStore().initialized;
    // Pin the in-memory legacy backend (the default routes to the query
    // backend, whose remove path needs seeded sources).
    await usePlayQueueStore().switchBackend(true);
  });

  setUp(() async {
    final store = usePlayQueueStore();
    await store.clear();
    await store.add([_f('a.mp4'), _f('b.mp4'), _f('c.mp4')]);
    // 'b' is the playing row — deliberately NOT the page-first row, so the
    // "deletes the first item on the page" stub cannot pass by accident.
    await store.updateCurrentIndex(1);
  });

  tearDown(() => usePlayQueueStore().clear());

  testWidgets(
      'trash with no selection deletes the current PLAYING row, '
      'not the page-first row', (tester) async {
    await tester.pumpWidget(_wrap(_page(PaginatedBrowserController())));
    await tester.pumpAndSettle();
    expect(find.text('b.mp4'), findsOneWidget);

    await _confirmTrashDelete(tester);

    expect(_queueNames(), ['a.mp4', 'c.mp4'],
        reason: 'the dialog promises the current playing row (b); deleting '
            'the page-first row (a) is the stub that must go');
    // The page must have re-read: the removed row is gone from the tree too.
    expect(find.text('b.mp4'), findsNothing);
    expect(find.text('a.mp4'), findsOneWidget);
  });

  testWidgets(
      'trash with no current playing row prompts nothing (nothing to delete)',
      (tester) async {
    // Non-empty queue, but no row resolves to this index: there is no
    // "current playing item", so per the dialog copy there is nothing to
    // delete and no confirmation may be offered.
    await usePlayQueueStore().updateCurrentIndex(99);

    await tester.pumpWidget(_wrap(_page(PaginatedBrowserController())));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing,
        reason: 'prompting with no playable target would fall through to a '
            'guess');
    expect(_queueNames(), ['a.mp4', 'b.mp4', 'c.mp4'],
        reason: 'nothing may be removed');
  });

  testWidgets(
      'selection-mode Remove deletes AND repaints (no stale row on screen)',
      (tester) async {
    final controller = PaginatedBrowserController<PlayQueueItem>();
    await tester.pumpWidget(_wrap(_page(controller)));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('b.mp4'));
    await tester.pumpAndSettle();
    expect(controller.isSelectionMode, isTrue);
    expect(controller.selectedIds, isNotEmpty);

    // Selection-mode bulk Remove: the only bulk delete reachable while a
    // selection exists (the trash renders in normal mode only).
    await tester.tap(find.byIcon(Icons.remove_circle_outline));
    await tester.pumpAndSettle();

    expect(_queueNames(), ['a.mp4', 'c.mp4'],
        reason: 'the selected row must actually leave the queue');
    expect(find.text('b.mp4'), findsNothing,
        reason: 'mutating the store without a refetch leaves the deleted row '
            'on screen until the user changes page');
  });

  // The selection branch is unit-covered rather than widget-driven: selection
  // mode replaces the bar, so the trash (normal mode only) is never tappable
  // WITH a selection in the current UI. The dialog copy still promises both
  // halves, so the resolver holds the contract.
  group('resolveTrashTargets', () {
    PlayQueueItem row(String name, int index) =>
        PlayQueueItem(file: _f(name), index: index);

    test('a non-empty selection wins over the playing row', () {
      final a = row('a.mp4', 0);
      final b = row('b.mp4', 1);
      final c = row('c.mp4', 2);
      expect(
        resolveTrashTargets(
          pageItems: [a, b, c],
          selection: {b},
          currentPlayingItem: c,
        ),
        [b],
      );
    });

    test('the selection is clipped to the rendered page', () {
      final a = row('a.mp4', 0);
      final offPage = row('z.mp4', 51);
      expect(
        resolveTrashTargets(
          pageItems: [a],
          selection: {a, offPage},
          currentPlayingItem: null,
        ),
        [a],
        reason: 'an id from another page must never widen the delete',
      );
    });

    test('no selection falls back to the playing row, even off-page', () {
      final a = row('a.mp4', 0);
      final playing = row('q.mp4', 70);
      expect(
        resolveTrashTargets(
          pageItems: [a],
          selection: const <PlayQueueItem>{},
          currentPlayingItem: playing,
        ),
        [playing],
        reason: 'the playing row is not guaranteed to be on this page',
      );
    });

    test('neither selection nor playing row -> no targets (no prompt)', () {
      expect(
        resolveTrashTargets(
          pageItems: [row('a.mp4', 0)],
          selection: const <PlayQueueItem>{},
          currentPlayingItem: null,
        ),
        isEmpty,
      );
    });
  });
}
