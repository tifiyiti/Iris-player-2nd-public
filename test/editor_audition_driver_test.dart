import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/engine/background_playback_engine.dart';
import 'package:iris/features/background_playback/model/domain/segment_edit_draft.dart';
import 'package:iris/features/background_playback/model/enum/mapping_action.dart';
import 'package:iris/features/background_playback/resolver/segment_span_math.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/features/background_playback/view/segment_align_edit_panel.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/models/store/app_state.dart' show PlayerBackend;
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:provider/provider.dart';
import 'package:zustand/zustand.dart';

/// The A-B editor must drive 副音 transport on the SIDE layout too. Before the
/// fix the side shell bypassed `_EditorAuditionDriver` while the generic
/// transport mirror stood down for `editing`, so 副音 had no driver at all on
/// the one-handed layout. These tests pin the driver's observable contract: the
/// span-gated join/st~p writes the store's `bgAutoPlay` flag.
MediaPlayer _player({required int posMs, required bool playing}) => MediaPlayer(
      isInitializing: false,
      isPlaying: playing,
      externalSubtitles: const [],
      position: Duration(milliseconds: posMs),
      duration: const Duration(hours: 1),
      buffer: Duration.zero,
      width: 16,
      height: 9,
      saveProgress: () async {},
      play: () async {},
      pause: () async {},
      backward: (_) async {},
      forward: (_) async {},
      stepBackward: () async {},
      stepForward: () async {},
      seek: (_) async {},
    );

Widget _shell(
  Widget body,
  BackgroundPlaybackEngine engine,
  MediaPlayer player,
) =>
    InheritedProvider<StoreLocator>.value(
      value: StoreLocator(),
      startListening: (InheritedContext<StoreLocator?> e, StoreLocator value) {
        final sub = value.changes.listen((_) => e.markNeedsNotifyDependents());
        return sub.cancel;
      },
      lazy: false,
      child: Provider<MediaPlayer>.value(
        value: player,
        child: ChangeNotifierProvider<BackgroundPlaybackEngine>.value(
          value: engine,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Align(alignment: Alignment.bottomRight, child: body),
            ),
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.plugins_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);
  setUpAll(() async {
    await DbModule.init(AppDatabase(NativeDatabase.memory()));
  });

  late BackgroundPlaybackEngine engine;
  setUp(() {
    engine = BackgroundPlaybackEngine(
      backend: PlayerBackend.mediaKit,
      attachNative: false,
    );
    useAppStore().set(useAppStore().state.copyWith(
          useMetadataSettings: true,
          useLegacyStoragePersistence: false,
        ));
    final queue = usePlayQueueStore();
    queue.set(queue.state.copyWith(
      playQueue: [
        const PlayQueueItem(
          file: FileItem(name: 'a.mp4', uri: 'file:///a.mp4'),
          index: 0,
        ),
      ],
      currentIndex: 0,
    ));
  });
  tearDown(() => engine.dispose());

  /// Puts the editor into an active playMedia session on the given span.
  void enterEdit({
    required SegmentSpan span,
    String? bgPath = 'local/B.mp4',
  }) {
    final bg = useBackgroundPlaybackStore();
    bg.set(bg.state.copyWith(
      enabled: true,
      gateOpen: true,
      segmentEditMode: true,
      segmentEditDraft: SegmentEditDraft(
        action: bgPath == null
            ? MappingAction.silence
            : MappingAction.playMedia,
        span: span,
        bgStorageId: bgPath == null ? null : 'local',
        bgPath: bgPath,
      ),
      bgAutoPlay: true,
    ));
  }

  testWidgets(
      'side layout: playhead OUTSIDE [A,B] pauses 副音 (overlay gates bg)',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    enterEdit(span: const SegmentSpan(fgStartMs: 10000, fgEndMs: 20000));
    // 副音 is currently PLAYING while the foreground paused before A: the
    // driver must stop it (this is the "can't control the linked bg" report).
    engine.duration = const Duration(minutes: 5);
    engine.isPlaying = true;
    await tester.pumpWidget(_shell(
      const SegmentAlignEditPanel(isSide: true),
      engine,
      _player(posMs: 1000, playing: false),
    ));
    await tester.pumpAndSettle();

    expect(useBackgroundPlaybackStore().state.bgAutoPlay, isFalse,
        reason: 'the side layout must mount the audition driver');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'side layout: playhead INSIDE [A,B] with fg playing joins 副音',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    enterEdit(span: const SegmentSpan(fgStartMs: 10000, fgEndMs: 20000));
    engine.duration = const Duration(minutes: 5);
    await tester.pumpWidget(_shell(
      const SegmentAlignEditPanel(isSide: true),
      engine,
      _player(posMs: 15000, playing: true),
    ));
    await tester.pumpAndSettle();

    expect(useBackgroundPlaybackStore().state.bgAutoPlay, isTrue,
        reason: 'inside [A,B] with fg playing, 副音 must be joined');
    expect(tester.takeException(), isNull);
  });

  testWidgets('linear layout also joins 副音 inside [A,B]', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    enterEdit(span: const SegmentSpan(fgStartMs: 10000, fgEndMs: 20000));
    engine.duration = const Duration(minutes: 5);
    await tester.pumpWidget(_shell(
      const SegmentAlignEditPanel(isSide: false),
      engine,
      _player(posMs: 15000, playing: true),
    ));
    await tester.pumpAndSettle();

    expect(useBackgroundPlaybackStore().state.bgAutoPlay, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a silence draft never joins 副音 even inside the span',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    enterEdit(
      span: const SegmentSpan(fgStartMs: 10000, fgEndMs: 20000),
      bgPath: null,
    );
    engine.duration = const Duration(minutes: 5);
    engine.isPlaying = true;
    await tester.pumpWidget(_shell(
      const SegmentAlignEditPanel(isSide: true),
      engine,
      _player(posMs: 15000, playing: true),
    ));
    await tester.pumpAndSettle();

    expect(useBackgroundPlaybackStore().state.bgAutoPlay, isFalse,
        reason: 'a silence draft must keep 副音 stopped');
    expect(tester.takeException(), isNull);
  });
}
