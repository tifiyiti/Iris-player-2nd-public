import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/features/background_playback/view/control_target_indicator.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/store/title_overlay_config.dart';
import 'package:iris/pages/player/control_bar/title_area.dart';
import 'package:iris/pages/player/title_bar.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:provider/provider.dart';
import 'package:zustand/zustand.dart';

/// Follow-up feedback: the 副音 state is signalled by APPENDING the background
/// media's name to the bar title in the accent color — the foreground title,
/// queue prefix and tag suffix must all survive untouched.
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

Widget _harness({String? bgTitleSuffix, bool bgTitleNoMedia = false}) {
  return _providerScope(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: TitleArea(
          title: 'foreground.mp4',
          queueLabel: '3/12',
          tagSuffix: 'TagA',
          bgTitleSuffix: bgTitleSuffix,
          bgTitleNoMedia: bgTitleNoMedia,
          color: Colors.white,
          overlayColor: null,
          saveProgress: () async {},
          config: const TitleOverlayConfig(),
        ),
      ),
    ),
  );
}

TextStyle? _styleOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  setUp(() {
    final app = useAppStore();
    app.set(app.state.copyWith(
      useMetadataSettings: true,
      useLegacyStoragePersistence: false,
      useClassicTitleBar: false,
    ));
  });

  tearDown(() => StoreLocator().delete(BackgroundPlaybackStore));

  testWidgets('no 副音 marker when the suffix is absent', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();
    expect(find.text('foreground.mp4'), findsOneWidget);
    expect(find.textContaining('Sub Audio'), findsNothing);
  });

  testWidgets('the marker is APPENDED, never substituted for the title',
      (tester) async {
    await tester.pumpWidget(_harness(bgTitleSuffix: 'Sub Audio ▸ bg.mp3'));
    await tester.pumpAndSettle();

    // The foreground subject and its queue/tag context are all still there.
    expect(find.text('foreground.mp4'), findsOneWidget);
    expect(find.text('3/12'), findsOneWidget);
    expect(find.textContaining('TagA'), findsOneWidget);
    // …and the 副音 name is appended alongside them.
    expect(find.text('Sub Audio ▸ bg.mp3'), findsOneWidget);
  });

  testWidgets('the marker renders in the accent color', (tester) async {
    await tester.pumpWidget(_harness(bgTitleSuffix: 'Sub Audio ▸ bg.mp3'));
    await tester.pumpAndSettle();
    expect(_styleOf(tester, 'Sub Audio ▸ bg.mp3')?.color,
        kBackgroundTargetColor);
  });

  testWidgets('the marker shares the title size/weight (only color differs)',
      (tester) async {
    await tester.pumpWidget(_harness(bgTitleSuffix: 'Sub Audio ▸ bg.mp3'));
    await tester.pumpAndSettle();
    final titleStyle = _styleOf(tester, 'foreground.mp4');
    final markerStyle = _styleOf(tester, 'Sub Audio ▸ bg.mp3');
    expect(markerStyle?.fontSize, titleStyle?.fontSize);
    expect(markerStyle?.fontWeight, isNot(FontWeight.w600));
  });

  testWidgets('no loaded 副音 media renders the marker muted (gray)',
      (tester) async {
    await tester.pumpWidget(_harness(
      bgTitleSuffix: 'Sub Audio ▸ —',
      bgTitleNoMedia: true,
    ));
    await tester.pumpAndSettle();
    expect(_styleOf(tester, 'Sub Audio ▸ —')?.color, Colors.white54);
  });

  testWidgets('order is title → tag → 副音 (overlay bar)', (tester) async {
    await tester.pumpWidget(_harness(bgTitleSuffix: 'Sub Audio ▸ bg.mp3'));
    await tester.pumpAndSettle();

    final double titleX =
        tester.getCenter(find.text('foreground.mp4')).dx;
    final double tagX =
        tester.getCenter(find.textContaining('TagA')).dx;
    final double bgX =
        tester.getCenter(find.text('Sub Audio ▸ bg.mp3')).dx;
    expect(titleX, lessThan(tagX));
    expect(tagX, lessThan(bgX));
  });

  testWidgets('order is title → tag → 副音 (classic bar)', (tester) async {
    await tester.pumpWidget(_providerScope(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: TitleBar(
            title: 'foreground.mp4',
            queueLabel: '3/12',
            tagSuffix: 'TagA',
            bgTitleSuffix: 'Sub Audio ▸ bg.mp3',
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final double titleX =
        tester.getCenter(find.text('foreground.mp4')).dx;
    final double tagX =
        tester.getCenter(find.textContaining('TagA')).dx;
    final double bgX =
        tester.getCenter(find.text('Sub Audio ▸ bg.mp3')).dx;
    expect(titleX, lessThan(tagX));
    expect(tagX, lessThan(bgX));
  });
}
