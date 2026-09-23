import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/progress.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_history_store.dart';
import 'package:iris/widgets/popups/history.dart';
import 'package:provider/provider.dart' show InheritedProvider;
import 'package:zustand/zustand.dart';

/// Browse-media-scope wiring for the history popup: entries whose file is
/// out-of-scope are hidden from the display list (persistence untouched).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
  });

  tearDown(() async {
    final store = useAppStore();
    store.set(store.state.copyWith(
      browseMediaScope: BrowseMediaScope.all,
      useMetadataSettings: false,
    ));
  });

  /// Keeps the global StoreLocator alive across tests (StoreScope would
  /// dispose it on unmount and race the next test's stores).
  Widget providerScope(Widget child) {
    return InheritedProvider<StoreLocator>.value(
      value: StoreLocator(),
      startListening: (context, value) {
        final sub = value.changes.listen((_) {});
        return sub.cancel;
      },
      lazy: false,
      child: child,
    );
  }

  Future<void> pumpHistory(WidgetTester tester) async {
    await tester.pumpWidget(providerScope(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: History()),
    )));
    await tester.pumpAndSettle();
  }

  void seedHistory() {
    FileItem file(String name, ContentType type) => FileItem(
          name: name,
          uri: 'file:///x/$name',
          path: ['x', name],
          type: type,
        );
    final now = DateTime.now();
    useHistoryStore().set(useHistoryStore().state.copyWith(history: {
      'k-v': Progress(
        dateTime: now,
        position: Duration.zero,
        duration: const Duration(minutes: 1),
        file: file('hist-video.mp4', ContentType.video),
      ),
      'k-a': Progress(
        dateTime: now.subtract(const Duration(seconds: 1)),
        position: Duration.zero,
        duration: const Duration(minutes: 1),
        file: file('hist-audio.mp3', ContentType.audio),
      ),
    }));
  }

  testWidgets('videoOnly hides audio history entries', (tester) async {
    seedHistory();
    await useAppStore().setMetadataGate(true);
    await useAppStore().updateBrowseMediaScope(BrowseMediaScope.videoOnly);

    await pumpHistory(tester);

    expect(find.text('hist-video.mp4'), findsOneWidget);
    expect(find.text('hist-audio.mp3'), findsNothing);
  });

  testWidgets('gate OFF shows every entry (legacy)', (tester) async {
    seedHistory();
    await useAppStore().setMetadataGate(false);

    await pumpHistory(tester);

    expect(find.text('hist-video.mp4'), findsOneWidget);
    expect(find.text('hist-audio.mp3'), findsOneWidget);
  });
}
