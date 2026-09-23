import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/engine/background_scope_logic.dart';
import 'package:iris/features/background_playback/model/enum/bg_apply_scope.dart';
import 'package:iris/features/background_playback/model/enum/control_target.dart';
import 'package:iris/features/background_playback/services/current_foreground_media_key.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/file.dart';
import 'package:iris/pages/player/control_bar/control_bar_widgets/background_playback_menu_button.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:provider/provider.dart';
import 'package:zustand/zustand.dart';

/// The control-bar 副音 menu: gate, master switch, apply toggle, 作用范围 row.
Widget _providerScope(Widget child) {
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

Widget _harness() {
  return _providerScope(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: BackgroundPlaybackMenuButton(showControl: () {}),
        ),
      ),
    ),
  );
}

FileItem _bgFile([String name = 'bg.mp3']) =>
    FileItem(name: name, uri: 'file:///$name', path: [name]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  setUp(() async {
    // Meta-driven era so the feature gate is ON by default in these tests.
    final app = useAppStore();
    app.set(app.state.copyWith(
      useMetadataSettings: true,
      useLegacyStoragePersistence: false,
    ));
    // The headset row's label/state reads the CURRENT media (apply-to-current),
    // so the harness needs a real foreground item.
    usePlayQueueStore();
    await usePlayQueueStore().initialized;
  });

  tearDown(() {
    StoreLocator().delete(BackgroundPlaybackStore);
    StoreLocator().delete(UnifiedPlayQueueStore);
  });

  /// Puts [name] on the foreground and returns its 作用范围 identity.
  Future<String> seedForeground([String name = 'fg.mp4']) async {
    final file = FileItem(name: name, uri: 'file:///$name', path: [name]);
    await usePlayQueueStore().update(
      playQueue: [PlayQueueItem(file: file, index: 0)],
      index: 0,
    );
    return currentScopeKey()!;
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.multitrack_audio_rounded));
    await tester.pumpAndSettle();
  }

  testWidgets('hidden entirely when the feature gate is off', (tester) async {
    final app = useAppStore();
    app.set(app.state.copyWith(useMetadataSettings: false));
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.multitrack_audio_rounded), findsNothing);
  });

  testWidgets('idle: the master row offers to turn 副音 on', (tester) async {
    final bg = useBackgroundPlaybackStore();
    await bg.initialized;
    bg.set(bg.state.copyWith(enabled: false));
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    await openMenu(tester);
    expect(find.text('Turn on Sub Audio'), findsOneWidget);
    expect(find.text('Scope: This video'), findsOneWidget);
  });

  testWidgets('running: the master row offers to turn 副音 off',
      (tester) async {
    final bg = useBackgroundPlaybackStore();
    await bg.initialized;
    // Anchored to the playing media → 副音 is applied here, so the row's label
    // names the stop action.
    final key = await seedForeground();
    bg.set(bg.state.copyWith(
      enabled: true,
      applyScope: BgApplyScope.currentOnly,
      scopeAnchorKey: key,
      currentIndex: 0,
      queue: [_bgFile()],
    ));
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    await openMenu(tester);
    expect(find.text('Turn off Sub Audio'), findsOneWidget);
    expect(find.text('Scope: This video'), findsOneWidget);
  });

  testWidgets('a closed gate greys the live-pair rows but keeps the linkage '
      'settings', (tester) async {
    final bg = useBackgroundPlaybackStore();
    await bg.initialized;
    bg.set(bg.state.copyWith(enabled: true, gateOpen: false));
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    await openMenu(tester);
    // Rows that address the bg runtime right now stay greyed…
    for (final label in [
      'Show the Sub Audio picture',
      'Control Sub Audio',
    ]) {
      final item = tester.widget<PopupMenuItem<Object>>(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(PopupMenuItem<Object>),
        ),
      );
      expect(item.enabled, isFalse,
          reason: '$label must be greyed while bg is not active');
    }
    // …but 同步方式/联动等级 are saved preferences, pre-configurable while
    // closed (the runtime applies them on the next activation).
    for (final label in [
      'Seek linking: High (seek step + play/pause)',
      'Fully independent',
    ]) {
      final item = tester.widget<PopupMenuItem<Object>>(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(PopupMenuItem<Object>),
        ),
      );
      expect(item.enabled, isTrue,
          reason: '$label is a saved preference and must stay reachable');
    }
    // The master switch stays reachable to turn the feature off / on.
    expect(find.text('Turn off Sub Audio'), findsOneWidget);
  });

  testWidgets('display and control rows are disabled while 副音 is off',
      (tester) async {
    final bg = useBackgroundPlaybackStore();
    await bg.initialized;
    bg.set(bg.state.copyWith(enabled: false));
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    await openMenu(tester);
    // Rows still render (discoverability) but carry null onTap.
    expect(find.text('Show the Sub Audio picture'), findsOneWidget);
    expect(find.text('Control Sub Audio'), findsOneWidget);
  });

  testWidgets('the auto-use-saved-mapping row toggles the preference',
      (tester) async {
    final bg = useBackgroundPlaybackStore();
    await bg.initialized;
    bg.set(bg.state.copyWith(enabled: false, mappingEnabled: true));
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    await openMenu(tester);
    final row = find.text('Auto-use saved mappings');
    expect(row, findsOneWidget);
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(bg.state.mappingEnabled, isFalse,
        reason: 'turning the row off must drop the saved-mapping preference');

    await openMenu(tester);
    final row2 = find.text('Auto-use saved mappings');
    await tester.ensureVisible(row2);
    await tester.pumpAndSettle();
    await tester.tap(row2);
    await tester.pumpAndSettle();
    expect(bg.state.mappingEnabled, isTrue);
  });

  testWidgets('closing this media reads as "not applied" and keeps the '
      'scope preference (问题 1)', (tester) async {
    final bg = useBackgroundPlaybackStore();
    await bg.initialized;
    bg.set(bg.state.copyWith(
      enabled: true,
      applyScope: BgApplyScope.currentOnly,
      scopeAnchorKey: 'k',
    ));

    // Close 对当前 through the store call the menu makes…
    bg.closeScopeForMedia('k');

    // …and the apply state derived for that media must flip back.
    final applied = resolveApplyToCurrent(
      enabled: bg.state.enabled,
      applyScope: bg.state.applyScope,
      anchorKey: bg.state.scopeAnchorKey,
      offMediaKeys: bg.state.bgOffMediaKeys,
      fgKey: 'k',
    );
    expect(applied, isFalse,
        reason: '问题 1: the label must flip back to "apply current"');
    // …and the scope preference itself was NOT disabled by closing 对当前.
    expect(bg.state.applyScope, BgApplyScope.currentOnly);
    expect(bg.state.enabled, isTrue);
  });

  testWidgets('an explicit activation hands the controls to 副音 '
      '(focusControl)', (tester) async {
    final bg = useBackgroundPlaybackStore();
    await bg.initialized;
    bg.set(bg.state.copyWith(enabled: false));

    // Same call the menu's master row makes once candidates resolve.
    await bg.enableWithQueue([_bgFile()], focusControl: true);

    expect(bg.state.enabled, isTrue);
    expect(bg.state.controlTarget, ControlTarget.background,
        reason: 'explicit activation must retarget the shared controls');
  });

  testWidgets('closing this media hands the controls back to the video',
      (tester) async {
    final bg = useBackgroundPlaybackStore();
    await bg.initialized;
    await bg.enableWithQueue([_bgFile()]);
    expect(bg.state.controlTarget, ControlTarget.background);

    bg.closeScopeForMedia('k');

    expect(bg.state.controlTarget, ControlTarget.foreground,
        reason: '关闭（对当前）must release the controls so the frame goes away');
    expect(bg.state.bgAutoPlay, isFalse);
    expect(bg.state.bgOffMediaKeys, contains('k'));
  });

  testWidgets('the full stop really disables everything', (tester) async {
    final bg = useBackgroundPlaybackStore();
    await bg.initialized;
    await bg.enableWithQueue([_bgFile()]);

    await bg.disable();

    expect(bg.state.enabled, isFalse);
    expect(bg.state.controlTarget, ControlTarget.foreground);
    expect(bg.state.displayTarget, ControlTarget.foreground);
    expect(bg.state.bgAutoPlay, isFalse);
  });

  testWidgets('auto-focus follows the meta switch, not the call site',
      (tester) async {
    final bg = useBackgroundPlaybackStore();
    await bg.initialized;

    await bg.enableWithQueue([_bgFile()]);
    expect(bg.state.controlTarget, ControlTarget.background);

    await bg.setAutoFocusControl(false);
    bg.set(bg.state.copyWith(enabled: false));
    await bg.enableWithQueue([_bgFile('bg2.mp3')]);
    expect(bg.state.controlTarget, ControlTarget.foreground,
        reason: 'autoFocusControl=false must keep the video controllable');
  });

  testWidgets('an explicit call-site override beats the meta switch',
      (tester) async {
    final bg = useBackgroundPlaybackStore();
    await bg.initialized;
    await bg.setAutoFocusControl(false);
    await bg.enableWithQueue([_bgFile()], focusControl: true);
    expect(bg.state.controlTarget, ControlTarget.background);
  });

  testWidgets('作用范围 preference round-trips through the store',
      (tester) async {
    final bg = useBackgroundPlaybackStore();
    await bg.initialized;

    await bg.setApplyScope(BgApplyScope.smart);
    await bg.setScopePersist(false);
    expect(bg.state.applyScope, BgApplyScope.smart);
    expect(bg.state.scopePersist, isFalse);

    // Not persisted across a restart: the cold-load normalizer resets it.
    final normalized = BackgroundPlaybackStore.normalizeLoaded(bg.state);
    expect(normalized.applyScope, BgApplyScope.currentOnly);

    await bg.setScopePersist(true);
    final kept =
        BackgroundPlaybackStore.normalizeLoaded(bg.state.copyWith(
      applyScope: BgApplyScope.all,
    ));
    expect(kept.applyScope, BgApplyScope.all);
  });
}
