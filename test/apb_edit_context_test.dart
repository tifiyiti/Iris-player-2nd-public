import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/services/apb_edit_context.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/file.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';

/// Spike: entering the APB edit context installs a single-fg transient
/// workspace and switches to it WITHOUT touching SystemPlaying; exiting
/// restores the previous context and deletes the transient workspace.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  setUpAll(() async {
    await DbModule.init(AppDatabase(NativeDatabase.memory()));
    usePlaybackScenarioStore();
    await usePlaybackScenarioStore().initialized;
    await runZonedGuarded(() async {
      usePlayQueueStore();
      await usePlayQueueStore().initialized;
      useAppStore();
      await useAppStore().initialized;
    }, (Object e, StackTrace st) {});
  });

  test('enter isolates SystemPlaying; exit restores it and deletes the draft',
      () async {
    final store = usePlaybackScenarioStore();
    await store.ensureReady();
    final sys = await store.ensureSystemPlayingScenario();
    await store.setActiveScenario(sys.id);
    await store.clearSources(sys.id);
    await store.clearExplicitItems(sys.id);
    await store.clearTemporaryExcludes(sys.id);
    await store.addExplicitItemFor(
      scenarioId: sys.id,
      storageId: 'st',
      path: 'Anime/Keep.mp4',
    );

    Future<void> fakeSwitch(String id) => store.setActiveScenario(id);

    const fg = FileItem(
      storageId: 'st',
      name: 'Ep01.mp4',
      uri: 'file:///Anime/Ep01.mp4',
      path: ['Anime', 'Ep01.mp4'],
    );

    final session = await ApbEditContext.enter(
      fg: fg,
      store: store,
      switchContext: fakeSwitch,
    );
    expect(session, isNotNull);
    expect(store.state.activeScenarioId, session!.workspaceId);

    // SystemPlaying keeps its own item.
    final sysItems = await store.getExplicitItems(sys.id);
    expect(sysItems.map((e) => e.path), contains('Anime/Keep.mp4'));

    // The transient workspace holds ONLY the edited foreground.
    final wsItems = await store.getExplicitItems(session.workspaceId);
    expect(wsItems, hasLength(1));
    expect(wsItems.single.path, 'Anime/Ep01.mp4');

    await ApbEditContext.exit(session, store: store, switchContext: fakeSwitch);

    expect(store.state.activeScenarioId, sys.id);
    expect(await store.getScenario(session.workspaceId), isNull);
    // SystemPlaying is still intact after the round trip.
    expect(
      (await store.getExplicitItems(sys.id)).map((e) => e.path),
      contains('Anime/Keep.mp4'),
    );
  });
}
