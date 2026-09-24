import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/media_lib/media_node.dart';
import 'package:iris/features/media_library/view/content/data_source/lib_content_data_source.dart';
import 'package:iris/features/media_library/view/content/model/lib_content_item.dart';
import 'package:iris/features/media_library/view/content/store/media_lib_content_runtime_state.dart';
import 'package:iris/features/media_library/view/content/store/use_media_lib_content_store.dart';
import 'package:iris/features/media_library/view/files_db_paging/storage_browser_data_source.dart';
import 'package:iris/features/media_library/view/tab/store/libs/enum/load_state.dart';
import 'package:iris/features/scenario_playback/playback/playback_provider_registry.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/l10n/app_localizations_zh.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/store/use_storage_store.dart';
import 'package:iris/store/warning_dialogs.dart';
import 'package:iris/widgets/dialogs/show_confirm_suppressible_dialog.dart';
import 'package:iris/widgets/popup.dart';

/// Regression: tapping a playable file inside the StoragesDb popup must not
/// race the play flow's first-use notice.
///
/// `_playFromCurrentDir` reaches `runPlayAction(WithNoMediaConfirm)` →
/// `_maybeShowWorkspaceNotice` → `showDialog` SYNCHRONOUSLY (before its first
/// await), so the notice lands on the same root navigator as the `Popup` route.
/// The old unawaited `Navigator.pop(context)` therefore dismissed the notice
/// instead of the popup: the notice flashed, playback was cancelled (no button
/// was ever pressed, so it was never suppressed) and the popup stayed open.
///
/// The popup must only close after a play that actually started, and a failing
/// play must leave the popup (and its error / No-Media surface) visible.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  setUpAll(() async {
    await DbModule.init(AppDatabase(NativeDatabase.memory()));
    useMediaLibContentStore();
    await useMediaLibContentStore().initialized;
    usePlaybackScenarioStore();
    await usePlaybackScenarioStore().initialized;
    PlaybackProviderRegistry.init();
    await runZonedGuarded(() async {
      usePlayQueueStore();
      await usePlayQueueStore().initialized;
      useAppStore();
      await useAppStore().initialized;
      useStorageStore();
      await useStorageStore().initialized;
    }, (Object e, StackTrace st) {});
  });

  setUp(() async {
    final app = useAppStore();
    app.set(app.state.copyWith(
      useLegacyStoragePersistence: false,
      useScenarioDrivenPlayback: true,
    ));
    usePlaybackScenarioStore().setStoragesDbStayOnPlay(false);
  });

  testWidgets(
      'storagedb tap: the first-use workspace notice survives the tap '
      '(the popup must not be popped over it)', (tester) async {
    await tester.runAsync(() async {
      // The notice is shown while its id is NOT suppressed — the fresh-install
      // state, and the only window in which the race is reachable.
      await useAppStore().resetSuppressedWarnings();

      final tempDir = await Directory.systemTemp.createTemp('tap_race_sb');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      File('${tempDir.path}/v.mp4').writeAsStringSync('');

      final storage = Storage.local(
        type: StorageType.internal,
        name: 't',
        basePath: [tempDir.path],
      );
      final ds = StorageBrowserDataSource(storage);
      addTearDown(ds.dispose);
      await ds.loadFromStorage();
      final item = ds.items.firstWhere((f) => f.isPlayable);

      final log = _RouteLog();
      await _openPopup(
        tester,
        log: log,
        onTap: (ctx) {
          ds.handleItemTap(ctx, item);
        },
      );
      await tester.tap(find.text('tap item'));
      await tester.pump();

      // The notice must be on screen...
      expect(find.byType(ConfirmSuppressibleDialog), findsOneWidget,
          reason: 'the play flow pushed the first-use notice');
      // ...and nothing may have consumed the popup route for it.
      expect(log.popupPops, 0,
          reason: 'the tap must not pop the popup while the notice is up');
      expect(find.text('tap item'), findsOneWidget);
    });
  });

  testWidgets('storagedb tap: a started play closes the popup', (tester) async {
    await tester.runAsync(() async {
      // The legacy branch sets the queue synchronously, so "playback started"
      // is deterministic here (no resolver / player involvement). This locks in
      // that a successful play STILL closes the popup — the fix must not
      // degrade into "never closes".
      final app = useAppStore();
      app.set(app.state.copyWith(useLegacyStoragePersistence: true));

      final item = _ghostFileItem('ok.mp4');
      final ds = _contentDataSourceWith(item);
      addTearDown(ds.dispose);

      final log = _RouteLog();
      await _openPopup(
        tester,
        log: log,
        onTap: (ctx) {
          ds.handleItemTap(ctx, item);
        },
      );
      await tester.tap(find.text('tap item'));

      await _pumpUntil(tester, () async => _played('ok.mp4'),
          'the play did not land');
      await _pumpUntil(tester, () async => log.popupPops == 1,
          'the popup did not close after a successful play');
      await tester.pump(const Duration(milliseconds: 300)); // popup exit
      expect(find.text('tap item'), findsNothing);
    });
  });

  testWidgets('storagedb tap: the stay-on-play pin keeps the popup open',
      (tester) async {
    await tester.runAsync(() async {
      final app = useAppStore();
      app.set(app.state.copyWith(useLegacyStoragePersistence: true));
      usePlaybackScenarioStore().setStoragesDbStayOnPlay(true);

      final item = _ghostFileItem('pin.mp4');
      final ds = _contentDataSourceWith(item);
      addTearDown(ds.dispose);

      final log = _RouteLog();
      await _openPopup(
        tester,
        log: log,
        onTap: (ctx) {
          ds.handleItemTap(ctx, item);
        },
      );
      await tester.tap(find.text('tap item'));

      await _pumpUntil(tester, () async => _played('pin.mp4'),
          'the play did not land');
      expect(log.popupPops, 0,
          reason: 'the pin must keep the popup open after a successful play');
      expect(find.text('tap item'), findsOneWidget);
    });
  });

  testWidgets(
      'storagedb tap: a failed play keeps the popup and surfaces the error',
      (tester) async {
    await tester.runAsync(() async {
      await useAppStore().suppressWarning(kWarningScenarioWorkspace);

      final tempDir = await Directory.systemTemp.createTemp('tap_fail_sb');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      File('${tempDir.path}/v.mp4').writeAsStringSync('');

      final storage = Storage.local(
        type: StorageType.internal,
        name: 't',
        basePath: [tempDir.path],
      );
      final ds = StorageBrowserDataSource(storage);
      addTearDown(ds.dispose);
      await ds.loadFromStorage();
      final item = ds.items.firstWhere((f) => f.isPlayable);

      // The folder scope is now empty in the media DB, so the playability
      // pre-check fails — the tap must NOT close the popup over the failure.
      await DbModule.mediaNodesDao.deleteByStorage(storage.id);

      final log = _RouteLog();
      await _openPopup(
        tester,
        log: log,
        onTap: (ctx) {
          ds.handleItemTap(ctx, item);
        },
      );
      await tester.tap(find.text('tap item'));

      await _pumpUntil(tester, () async => tester.any(find.byType(SelectableText)),
          'the failed play did not surface the copyable error dialog');
      expect(log.popupPops, 0, reason: 'a failed play must keep the popup open');
      expect(find.text('tap item'), findsOneWidget);
    });
  });

  testWidgets(
      'lib content tap: the first-use workspace notice survives the tap '
      '(the popup must not be popped over it)', (tester) async {
    await tester.runAsync(() async {
      await useAppStore().resetSuppressedWarnings();

      final item = _ghostFileItem();
      final ds = _contentDataSourceWith(item);
      addTearDown(ds.dispose);

      final log = _RouteLog();
      await _openPopup(
        tester,
        log: log,
        onTap: (ctx) {
          ds.handleItemTap(ctx, item);
        },
      );
      await tester.tap(find.text('tap item'));
      await tester.pump();

      expect(find.byType(ConfirmSuppressibleDialog), findsOneWidget,
          reason: 'the play flow pushed the first-use notice');
      expect(log.popupPops, 0,
          reason: 'the tap must not pop the popup while the notice is up');
      expect(find.text('tap item'), findsOneWidget);
    });
  });

  testWidgets(
      'lib content tap: an unplayable scope shows the No Media confirm instead '
      'of a silent no-op', (tester) async {
    await tester.runAsync(() async {
      await useAppStore().suppressWarning(kWarningScenarioWorkspace);

      final item = _ghostFileItem();
      final ds = _contentDataSourceWith(item);
      addTearDown(ds.dispose);

      final log = _RouteLog();
      await _openPopup(
        tester,
        log: log,
        onTap: (ctx) {
          ds.handleItemTap(ctx, item);
        },
      );
      await tester.tap(find.text('tap item'));

      await _pumpUntil(tester, () async => tester.any(find.byType(ConfirmSuppressibleDialog)),
          'the unplayable scope did not surface the No Media confirm');
      expect(log.popupPops, 0,
          reason: 'the popup must stay open until playback starts');
      expect(find.text('tap item'), findsOneWidget);
    });
  });
}

/// A file row for a storage with no media_nodes rows, so the folder-scope
/// playability pre-check resolves to nothing (deterministic failure). [name] is
/// unique per test so the play-latch assertion cannot be satisfied by a queue
/// another test left behind.
NodeLibContentItem _ghostFileItem([String name = 'x.mp4']) =>
    NodeLibContentItem(MediaNode.file(
      id: 'f:ghost:$name',
      storageId: 'ghost',
      path: [name],
      name: name,
      mediaType: MediaType.video,
    ));

/// True once the legacy branch queued [name] — the deterministic "playback
/// started" latch (the scenario branch needs a resolver + player).
bool _played(String name) =>
    usePlayQueueStore().state.playQueue.any((i) => i.file.name == name);

LibContentDataSource _contentDataSourceWith(NodeLibContentItem item) {
  useMediaLibContentStore().debugSetRuntime(MediaLibContentRuntimeState(
    state: LoadState.ready,
    items: [item],
    currentPage: 1,
    totalPages: 1,
    totalItems: 1,
  ));
  return LibContentDataSource(useMediaLibContentStore());
}

/// Counts how often the `Popup` route itself was closed — the dialog routes
/// come and go as the play flow runs, so a plain pop counter cannot tell them
/// apart from the popup.
class _RouteLog extends NavigatorObserver {
  int popupPops = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is Popup) popupPops++;
  }
}

/// Hosts `handleItemTap` inside a pushed [Popup] route, mirroring the
/// storagedb popup the real surfaces live in.
Future<void> _openPopup(
  WidgetTester tester, {
  required _RouteLog log,
  required void Function(BuildContext popupCtx) onTap,
}) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: [
      const _SyncZhLocalizationsDelegate(),
      ...AppLocalizations.localizationsDelegates.skip(1),
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    navigatorObservers: [log],
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(
              Popup(
                direction: PopupDirection.right,
                child: Builder(
                  builder: (popupCtx) => TextButton(
                    onPressed: () => onTap(popupCtx),
                    child: const Text('tap item'),
                  ),
                ),
              ),
            ),
            child: const Text('open popup'),
          ),
        ),
      ),
    ),
  ));
  // Deferred l10n delegates load async — wait with real time for the localized
  // home subtree (fake-time pumpAndSettle returns too early).
  for (var i = 0; i < 200; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await tester.pump();
    if (find.text('open popup').evaluate().isNotEmpty) break;
  }
  await tester.tap(find.text('open popup'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300)); // popup entrance
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Future<bool> Function() cond,
  String message,
) async {
  for (var i = 0; i < 200; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await tester.pump();
    if (await cond()) return;
  }
  fail(message);
}

/// gen-l10n deferred chunks load only once per test isolate; serving zh
/// synchronously keeps `getLocalizations(context)` (used by the notice
/// dialog) from seeing a null localizations object.
class _SyncZhLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _SyncZhLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'zh';

  @override
  Future<AppLocalizations> load(Locale locale) async => AppLocalizationsZh();

  @override
  bool shouldReload(_SyncZhLocalizationsDelegate old) => false;
}
