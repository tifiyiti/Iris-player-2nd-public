import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/tag_play/view/widgets/tag_time_cells_input.dart';
import 'package:iris/l10n/app_localizations.dart';

void main() {
  group('tagDurationFromCells / tagCellsFromDuration', () {
    test('parses cells into a duration', () {
      final d = tagDurationFromCells(
        (y: 1, mo: 0, d: 0, h: 0, mi: 5, s: 0),
      );
      expect(d, const Duration(days: 365, minutes: 5));
    });

    test('clamps to the 5-minute lower bound', () {
      final d = tagDurationFromCells(
        (y: 0, mo: 0, d: 0, h: 0, mi: 0, s: 1),
      );
      expect(d, const Duration(minutes: 5));
    });

    test('clamps to the 99y99mo99d 99h99m99s upper bound', () {
      final maxSeconds = ((99 * 365 + 99 * 30 + 99) * 86400) +
          (99 * 3600 + 99 * 60 + 99);
      final d = tagDurationFromCells(
        (y: 99, mo: 99, d: 99, h: 99, mi: 99, s: 99),
      );
      expect(d, Duration(seconds: maxSeconds));

      final over = tagDurationFromCells(
        (y: 200, mo: 0, d: 0, h: 0, mi: 0, s: 0),
      );
      expect(over, Duration(seconds: maxSeconds));
    });

    test('round-trips through decomposition', () {
      final source = const Duration(hours: 30, minutes: 47, seconds: 12);
      final cells = tagCellsFromDuration(source);
      final back = tagDurationFromCells(cells);
      expect(back, source);
    });
  });

  group('TagTimeCellsInput widget', () {
    Widget harness({
      required Duration? initial,
      required ValueChanged<Duration?> onChanged,
    }) {
      return MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: TagTimeCellsInput(
              initial: initial,
              fallback: const Duration(hours: 6),
              onChanged: onChanged,
            ),
          ),
        ),
      );
    }

    testWidgets('typing two digits auto-advances focus to the next cell',
        (tester) async {
      final emitted = <Duration?>[];
      await tester.pumpWidget(harness(
        initial: null,
        onChanged: emitted.add,
      ));
      // Deferred l10n delegates load async — settle before interacting.
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing); // 永久 by default

      // Switch off 永久 → cells appear (prefilled with the 6h fallback).
      await tester.tap(find.text('永久'));
      await tester.pump();
      expect(find.byType(TextField), findsNWidgets(6));

      // Clear the fallback hour cell so day 12 is the only non-zero cell.
      await tester.enterText(find.byType(TextField).at(3), '00');
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(2), '12');
      await tester.pump();
      final next = tester.widget<TextField>(find.byType(TextField).at(3));
      expect(next.focusNode?.hasFocus, isTrue);

      expect(emitted, isNotEmpty);
      expect(emitted.last, const Duration(days: 12));
    });

    testWidgets('toggling 永久 emits null, re-enabling clamps to fallback',
        (tester) async {
      final emitted = <Duration?>[];
      await tester.pumpWidget(harness(
        initial: const Duration(hours: 2),
        onChanged: emitted.add,
      ));
      // Deferred l10n delegates load async — settle before tapping.
      await tester.pumpAndSettle();

      // Non-permanent: cells prefilled from initial (02时).
      expect(find.byType(TextField), findsNWidgets(6));
      final hourCell = tester.widget<TextField>(find.byType(TextField).at(3));
      expect(hourCell.controller?.text, '02');

      await tester.tap(find.text('永久'));
      await tester.pump();
      expect(emitted.last, isNull);

      await tester.tap(find.text('永久'));
      await tester.pump();
      expect(emitted.last, const Duration(hours: 2));
    });

    testWidgets('below-minimum input clamps to 5 minutes', (tester) async {
      final emitted = <Duration?>[];
      await tester.pumpWidget(harness(
        initial: null,
        onChanged: emitted.add,
      ));
      // Deferred l10n delegates load async — settle before interacting.
      await tester.pumpAndSettle();
      await tester.tap(find.text('永久'));
      await tester.pump();

      // Clear the fallback hours and set the seconds cell to 01 → total is
      // 1s < 5min → clamped to 5 minutes.
      await tester.enterText(find.byType(TextField).at(3), '00');
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(5), '01');
      await tester.pump();
      expect(emitted.last, const Duration(minutes: 5));
    });
  });
}