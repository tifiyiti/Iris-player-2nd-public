import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/actions/background_playback_actions.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:provider/provider.dart';
import 'package:zustand/zustand.dart';

import 'helpers/sqlite3_loader.dart';

Widget _harness() => InheritedProvider<StoreLocator>.value(
      value: StoreLocator(),
      startListening: (InheritedContext<StoreLocator?> e, StoreLocator value) {
        final sub = value.changes.listen((_) => e.markNeedsNotifyDependents());
        return sub.cancel;
      },
      lazy: false,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => BackgroundPlaybackActions.refresh(context),
              child: const Text('refresh'),
            ),
          ),
        ),
      ),
    );

void main() {
  ensureSqlite3Loaded();
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  late AppDatabase db;

  setUpAll(() async {
    // invalidateSourceRules() reaches BackgroundCandidateCache → DbModule.
    db = AppDatabase(NativeDatabase.memory());
    await DbModule.init(db);
  });

  tearDownAll(() => db.close());

  setUp(() async {
    final app = useAppStore();
    app.set(app.state.copyWith(
      useMetadataSettings: true,
      useLegacyStoragePersistence: false,
    ));
    final bg = useBackgroundPlaybackStore();
    await bg.initialized;
    await usePlayQueueStore().initialized;
    // The idle case: 副音 is NOT running when the user presses "Update now".
    if (bg.state.enabled) await bg.disable();
  });

  tearDown(() {
    StoreLocator().delete(BackgroundPlaybackStore);
    StoreLocator().delete(UnifiedPlayQueueStore);
  });

  testWidgets('"Update now" while idle explains there is nothing to update',
      (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('refresh'));
    await tester.pumpAndSettle();

    // The button used to return silently — a dead press with no feedback.
    expect(
      find.text('Sub Audio is not playing, so there is nothing to update now. '
          'Source changes apply the next time it starts.'),
      findsOneWidget,
    );
    expect(useBackgroundPlaybackStore().state.enabled, isFalse,
        reason: 'an idle refresh must never start 副音 as a side effect');
  });
}
