import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/windows/desktop_keyboard/view/show_jump_to_time_dialog.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/player.dart';

// Regression: the jump-to dialog is pushed on the ROOT navigator where no
// Provider<MediaPlayer> exists (it lives inside PlayerView), so its build
// threw ProviderNotFoundException and rendered Flutter's error screen.

MediaPlayer _player({
  Duration position = Duration.zero,
  Duration duration = const Duration(minutes: 10),
  void Function(Duration)? onSeek,
}) {
  return MediaPlayer(
    isInitializing: false,
    isPlaying: false,
    externalSubtitles: const [],
    position: position,
    duration: duration,
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
    seek: ((Duration d) async => onSeek?.call(d)),
  );
}

Widget _harness(MediaPlayer player) {
  return MaterialApp(
    localizationsDelegates: [
      ...AppLocalizations.localizationsDelegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (BuildContext ctx) => Center(
          child: FilledButton(
            onPressed: () => showJumpToTimeDialog(ctx, player),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('opens without MediaPlayer provider above root navigator',
      (WidgetTester tester) async {
    await tester.pumpWidget(_harness(_player()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('HH'), findsOneWidget);
    expect(find.text('MM'), findsOneWidget);
    expect(find.text('SS'), findsOneWidget);
  });

  testWidgets('Go seeks to the parsed position and pops',
      (WidgetTester tester) async {
    final List<Duration> seeks = <Duration>[];
    await tester.pumpWidget(_harness(_player(onSeek: seeks.add)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3));
    await tester.enterText(fields.at(1), '1');
    await tester.enterText(fields.at(2), '30');
    await tester.pump();
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    expect(seeks, <Duration>[const Duration(minutes: 1, seconds: 30)]);
    expect(find.text('HH'), findsNothing);
  });

  testWidgets('paste colon string dispatches to three boxes',
      (WidgetTester tester) async {
    final List<Duration> seeks = <Duration>[];
    await tester.pumpWidget(_harness(_player(
      duration: const Duration(hours: 2),
      onSeek: seeks.add,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '1:02:03');
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    expect(seeks, <Duration>[const Duration(hours: 1, minutes: 2, seconds: 3)]);
  });

  testWidgets('overflow warns and cancel keeps dialog',
      (WidgetTester tester) async {
    final List<Duration> seeks = <Duration>[];
    await tester.pumpWidget(_harness(_player(
      duration: const Duration(minutes: 1),
      onSeek: seeks.add,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), '5');
    await tester.pump();
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    expect(find.text('Continue'), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(find.text('HH'), findsOneWidget);
    expect(seeks, isEmpty);
  });

  testWidgets('overflow continue seeks to duration-1s',
      (WidgetTester tester) async {
    final List<Duration> seeks = <Duration>[];
    await tester.pumpWidget(_harness(_player(
      duration: const Duration(minutes: 1),
      onSeek: seeks.add,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), '5');
    await tester.pump();
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(seeks, <Duration>[const Duration(seconds: 59)]);
    expect(find.text('HH'), findsNothing);
  });

  test('tryComposeHMS allows large values and normalizes', () {
    expect(tryComposeHMS('100', '0', '0'),
        const Duration(hours: 100));
    expect(tryComposeHMS('0', '100', '0'),
        const Duration(minutes: 100)); // 1h40m
    expect(tryComposeHMS('0', '0', '10000'),
        const Duration(seconds: 10000));
    expect(tryComposeHMS('', '', ''), Duration.zero);
    expect(parseJumpToTimeInput('100:00'), const Duration(minutes: 100));
    expect(parseJumpToTimeInput('1:02:03'),
        const Duration(hours: 1, minutes: 2, seconds: 3));
  });
}
