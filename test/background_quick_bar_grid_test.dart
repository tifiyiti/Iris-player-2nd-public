import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/view/background_quick_bar_grid.dart';

/// The vertical 副音 quick strip flows into at most two columns when a short
/// one-handed panel cannot hold the full button set. These cases lock the
/// frequency-driven degradation: the fewest columns that fit, the rarest
/// buttons pushed to the second column / overflow, never more than 2 columns.
void main() {
  group('resolveQuickBarGrid column selection', () {
    // Heights are expressed through kQuickButtonExtent so the cases keep testing
    // the CONTRACT when the button footprint changes.
    test('a tall panel stays a single column', () {
      final g = resolveQuickBarGrid(
        buttonCount: 10,
        availableHeight: kQuickButtonExtent * 10,
        availableWidth: 300,
      );
      expect(g.columns, 1);
      expect(g.rows, 10);
      expect(g.fits, isTrue);
      expect(g.width, kQuickColExtent);
    });

    test('a five-row panel widens to two balanced columns', () {
      final g = resolveQuickBarGrid(
        buttonCount: 10,
        availableHeight: kQuickButtonExtent * 5,
        availableWidth: 300,
      );
      expect(g.columns, 2);
      expect(g.rows, 5);
      expect(g.fits, isTrue);
      expect(g.width, kQuickColExtent * 2 + kQuickSpacing);
    });

    test('one pixel short of five rows no longer fits two columns', () {
      final g = resolveQuickBarGrid(
        buttonCount: 10,
        availableHeight: kQuickButtonExtent * 5 - 1,
        availableWidth: 300,
      );
      expect(g.columns, 2);
      expect(g.fits, isFalse);
    });

    test('a four-row panel keeps two columns but scrolls (fits=false)', () {
      final g = resolveQuickBarGrid(
        buttonCount: 10,
        availableHeight: kQuickButtonExtent * 4,
        availableWidth: 300,
      );
      expect(g.columns, 2);
      expect(g.rows, 5);
      expect(g.fits, isFalse);
    });

    test('a three-row panel caps at two columns and scrolls', () {
      final g = resolveQuickBarGrid(
        buttonCount: 10,
        availableHeight: kQuickButtonExtent * 3,
        availableWidth: 300,
      );
      expect(g.columns, 2);
      expect(g.fits, isFalse);
    });

    test('seven buttons fit two columns at four rows', () {
      final g = resolveQuickBarGrid(
        buttonCount: 7,
        availableHeight: kQuickButtonExtent * 4,
        availableWidth: 200,
      );
      expect(g.columns, 2);
      expect(g.rows, 4);
      expect(g.fits, isTrue);
    });
  });

  group('resolveQuickBarGrid width capacity', () {
    test('too narrow for two columns degrades to one', () {
      final g = resolveQuickBarGrid(
        buttonCount: 10,
        availableHeight: kQuickButtonExtent * 10,
        availableWidth: 50,
      );
      expect(g.columns, 1);
      expect(g.fits, isTrue);
    });

    test('too narrow AND too short scrolls in one column', () {
      final g = resolveQuickBarGrid(
        buttonCount: 10,
        availableHeight: kQuickButtonExtent * 3,
        availableWidth: 50,
      );
      expect(g.columns, 1);
      expect(g.rows, 10);
      expect(g.fits, isFalse);
    });

    test('exactly two column widths are enough', () {
      final g = resolveQuickBarGrid(
        buttonCount: 10,
        availableHeight: kQuickButtonExtent * 5,
        availableWidth: kQuickColExtent * 2 + kQuickSpacing,
      );
      expect(g.columns, 2);
      expect(g.fits, isTrue);
    });
  });

  group('resolveQuickBarGrid degenerate inputs', () {
    test('no buttons yields an empty single column', () {
      final g = resolveQuickBarGrid(
        buttonCount: 0,
        availableHeight: 300,
        availableWidth: 300,
      );
      expect(g.columns, 1);
      expect(g.rows, 0);
      expect(g.width, 0);
      expect(g.fits, isTrue);
    });

    test('unbounded height stays a single column', () {
      final g = resolveQuickBarGrid(
        buttonCount: 10,
        availableHeight: double.infinity,
        availableWidth: 300,
      );
      expect(g.columns, 1);
      expect(g.fits, isTrue);
    });

    test('unbounded width is capped at the two-column product limit', () {
      final g = resolveQuickBarGrid(
        buttonCount: 10,
        availableHeight: 200,
        availableWidth: double.infinity,
      );
      expect(g.columns, kQuickMaxColumns);
    });
  });
}
