import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/widgets/controls/balanced_button_wrap.dart';

/// Contract for the side panel's balanced button block:
///
///  * rows are BALANCED (differ by at most one) with the extra buttons on the
///    BOTTOM rows — the opposite of `Wrap`'s greedy "fill top, remainder last";
///  * the block is measured, so a row never overflows the panel even when the
///    children have different widths (desktop volume strip).
void main() {
  group('balancedRowCounts', () {
    test('spreads the remainder onto the BOTTOM rows', () {
      expect(balancedRowCounts(11, 6), <int>[5, 6]);
      expect(balancedRowCounts(13, 6), <int>[4, 4, 5]);
      expect(balancedRowCounts(7, 6), <int>[3, 4]);
    });

    test('even splits stay even and a single row stays whole', () {
      expect(balancedRowCounts(12, 6), <int>[6, 6]);
      expect(balancedRowCounts(6, 6), <int>[6]);
      expect(balancedRowCounts(5, 6), <int>[5]);
    });

    test('empty / degenerate capacity never throws', () {
      expect(balancedRowCounts(0, 6), isEmpty);
      expect(balancedRowCounts(-3, 6), isEmpty);
      expect(balancedRowCounts(3, 0), <int>[1, 1, 1]);
    });
  });

  testWidgets('block balances 11 buttons over 2 rows: 5 on top, 6 below',
      (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            // Exactly fits 6 buttons (6*40 + 5*8 = 280).
            width: 280,
            child: BalancedButtonWrap(
              spacing: 8,
              runSpacing: 6,
              children: <Widget>[
                for (int i = 0; i < 11; i++)
                  SizedBox(key: ValueKey<int>(i), width: 40, height: 40),
              ],
            ),
          ),
        ),
      ),
    );

    double top(int i) => tester.getTopLeft(find.byKey(ValueKey<int>(i))).dy;

    // First row: indices 0..4 (5 buttons).
    for (int i = 0; i < 5; i++) {
      expect(top(i), top(0), reason: 'button $i belongs to the top row');
    }
    // Second row: indices 5..10 (6 buttons), BELOW the first row.
    for (int i = 5; i < 11; i++) {
      expect(top(i), top(5), reason: 'button $i belongs to the bottom row');
      expect(top(i), greaterThan(top(0)),
          reason: 'the extra buttons sit on the BOTTOM row');
    }

    // Block width is the widest row (6 buttons), height is two rows + run gap.
    expect(tester.getSize(find.byType(BalancedButtonWrap)),
        const Size(280, 40 + 6 + 40));
    expect(tester.takeException(), isNull);
  });

  testWidgets('rows never overflow when children have different widths',
      (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 280,
            child: BalancedButtonWrap(
              spacing: 8,
              runSpacing: 6,
              children: <Widget>[
                // A wide child followed by many narrow ones: a naive balance
                // would put the wide one in a 3-button row and overflow.
                const SizedBox(key: ValueKey<String>('wide'), width: 200, height: 40),
                for (int i = 0; i < 6; i++)
                  SizedBox(key: ValueKey<int>(i), width: 40, height: 40),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final Rect wide =
        tester.getRect(find.byKey(const ValueKey<String>('wide')));
    final Rect block = tester.getRect(find.byType(BalancedButtonWrap));
    expect(wide.left, greaterThanOrEqualTo(block.left - 0.01));
    expect(wide.right, lessThanOrEqualTo(block.right + 0.01));
  });
}
