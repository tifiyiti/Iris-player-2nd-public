import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/paginated_browser/models/browser_toolbar_layout.dart';
import 'package:iris/features/paginated_browser/models/generic_browser_models.dart';
import 'package:iris/features/paginated_browser/paginated_browser_controller.dart';
import 'package:iris/features/paginated_browser/paginated_browser_page.dart';
import 'package:iris/features/paginated_browser/widgets/browser_bar_primitives.dart';
import 'package:iris/features/paginated_browser/widgets/compact_single_row_bar.dart';
import 'package:iris/features/paginated_browser/widgets/dynamic_responsive_bar.dart';
import 'package:iris/features/paginated_browser/widgets/floating_grid_bar.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/widgets/controls/balanced_button_wrap.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'helpers/fake_paged_browser_data_source.dart';

/// V3 of the scenario play queue: a floating grid of square tiles drawn OVER
/// the list, translucent and draggable, with NO bottom bar at all.
///
/// Two properties carry the layout and must not regress:
///
/// * the list gets the full height (the bottom-bar section is gone, not merely
///   empty), and
/// * a drag repositions the bar by paint only and commits its fraction ONCE at
///   the end — never per frame, because Drift runs on the UI isolate.
void main() {
  // The bar is a fraction-positioned overlay, so every drag assertion needs a
  // real, finite host box to measure against.
  const Size host = Size(400, 640);

  Widget wrap(Widget child, {Size size = host}) {
    return StoreScope(
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SizedBox.fromSize(size: size, child: child)),
      ),
    );
  }

  Future<PaginatedBrowserController<String>> pumpPage(
    WidgetTester tester,
    FakePagedBrowserDataSource ds, {
    Offset? barOffset,
    ValueChanged<Offset>? onBarMoved,
    Size size = host,
  }) async {
    final controller = PaginatedBrowserController<String>();
    await tester.pumpWidget(wrap(
      PaginatedBrowserPage<String>(
        dataSource: ds,
        controller: controller,
        onClose: () {},
        showHomePage: false,
        showBackButton: false,
        toolbarLayout: BrowserToolbarLayout.floatingGrid,
        floatingBarOffset: barOffset,
        onFloatingBarMoved: onBarMoved,
      ),
      size: size,
    ));
    await tester.pumpAndSettle();
    return controller;
  }

  group('V3 chrome', () {
    testWidgets('renders no bottom bar at all, only the list',
        (tester) async {
      final ds = FakePagedBrowserDataSource(supportsCurrent: true);
      await pumpPage(tester, ds);

      expect(find.byType(FloatingGridBar<String>), findsOneWidget);
      expect(find.byType(DynamicResponsiveBar<String>), findsNothing);
      expect(find.byType(CompactSingleRowBar<String>), findsNothing);

      // Compared against V1 in the SAME harness rather than against the page box:
      // the list sits inside a `Card` with its own margin, so its height is
      // never the page height. What matters is that V3 reserves NO layout space
      // for a bar, so its list must come out strictly taller than V1's.
      final page = find.byType(PaginatedBrowserPage<String>);
      final list = find.descendant(
        of: page,
        matching: find.byType(ScrollablePositionedList),
      );
      final v3Height = tester.getSize(list).height;

      await tester.pumpWidget(wrap(
        PaginatedBrowserPage<String>(
          dataSource: ds,
          controller: PaginatedBrowserController<String>(),
          onClose: () {},
          showHomePage: false,
          showBackButton: false,
        ),
      ));
      await tester.pumpAndSettle();
      final v1Height = tester.getSize(list).height;

      expect(v3Height, greaterThan(v1Height),
          reason: 'V3 must not reserve layout space for a bottom bar');
    });

    testWidgets('keeps the V2 control set in the grid', (tester) async {
      final ds = FakePagedBrowserDataSource(supportsCurrent: true);
      await pumpPage(tester, ds);

      expect(find.byIcon(Icons.sort_rounded), findsOneWidget);
      expect(find.byIcon(Icons.navigate_before), findsOneWidget);
      expect(find.byIcon(Icons.navigate_next), findsOneWidget);
      expect(find.text('1/2'), findsOneWidget, reason: 'page counter');
      expect(find.text('10/5'), findsOneWidget, reason: 'total / per-page');
      expect(find.byIcon(Icons.my_location), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsOneWidget, reason: 'overflow');
      expect(find.byIcon(Icons.close), findsOneWidget);

      // Same folding rule as V2: nothing else renders inline.
      expect(find.byIcon(Icons.search), findsNothing);
      expect(find.byIcon(Icons.tune), findsNothing);
    });

    testWidgets('the close tile fires onClose', (tester) async {
      var closed = 0;
      final ds = FakePagedBrowserDataSource();
      final controller = PaginatedBrowserController<String>();
      await tester.pumpWidget(wrap(
        PaginatedBrowserPage<String>(
          dataSource: ds,
          controller: controller,
          onClose: () => closed++,
          showHomePage: false,
          showBackButton: false,
          toolbarLayout: BrowserToolbarLayout.floatingGrid,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(closed, 1);
    });

    testWidgets('folds custom + trailing actions into the overflow menu',
        (tester) async {
      final ds = FakePagedBrowserDataSource(
        supportsCurrent: true,
        customActions: [
          PageAction(
            icon: const Icon(Icons.search),
            label: 'search-action',
            onPressed: () {},
          ),
        ],
        trailingActions: [
          PageAction(
            icon: const Icon(Icons.view_sidebar_rounded),
            label: 'trailing-action',
            onPressed: () {},
          ),
        ],
      );
      await pumpPage(tester, ds);

      expect(find.text('search-action'), findsNothing);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text('search-action'), findsOneWidget);
      expect(find.text('trailing-action'), findsOneWidget);
    });

    testWidgets('overflow entries fire their action', (tester) async {
      var tapped = false;
      final ds = FakePagedBrowserDataSource(
        supportsCurrent: true,
        customActions: [
          PageAction(
            icon: const Icon(Icons.search),
            label: 'search-action',
            onPressed: () => tapped = true,
          ),
        ],
      );
      await pumpPage(tester, ds);
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('search-action'));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });

    testWidgets('selection mode swaps the grid for the selection set',
        (tester) async {
      var excluded = false;
      final ds = FakePagedBrowserDataSource(
        selectionActions: [
          CustomSelectionAction<String>(
            icon: const Icon(Icons.remove_circle_outline),
            label: 'exclude-selected',
            onPressed: (context, selected) async {
              excluded = true;
              return false;
            },
          ),
        ],
      );
      final controller = await pumpPage(tester, ds);

      controller.enterSelectionMode(ds.items.first, ds);
      await tester.pumpAndSettle();

      // Back / page nav / selected count / overflow / close.
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.my_location), findsNothing,
          reason: 'locate-current is not a selection action');
      expect(find.text('exclude-selected'), findsNothing);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('exclude-selected'));
      await tester.pumpAndSettle();
      expect(excluded, isTrue);
    });
  });

  group('V3 placement', () {
    /// Where the bar's first tile actually sits, in page coordinates.
    ///
    /// Reading the BAR's own box cannot answer this: the resting spot is a paint
    /// transform, so the bar's layout box stays pinned at the host origin and
    /// reports the same rectangle no matter where the bar is. A tile INSIDE the
    /// transform does move, and `getTopLeft` resolves the paint transform — so
    /// the bar's position is read off a tile.
    Offset barSpot(WidgetTester tester) =>
        tester.getTopLeft(find.byType(FloatingGridTile).first);

    /// How far the paint transform has moved the bar from the host's top-left.
    Offset barShift(WidgetTester tester) => barSpot(tester);

    /// Pumps the page at [fraction] and returns the tracked tile's spot.
    Future<Offset> barSpotAfter(
      WidgetTester tester,
      FakePagedBrowserDataSource ds,
      Offset fraction,
    ) async {
      await pumpPage(tester, ds, barOffset: fraction);
      return barSpot(tester);
    }

    testWidgets('the fraction spans the host corner to corner', (tester) async {
      // (0,0) parks the bar in the top-left corner, (1,1) in the bottom-right.
      // Asserted as the DISTANCE BETWEEN the two spots rather than their
      // absolute positions: the tracked tile sits at a fixed inset inside the
      // bar (its own padding), so the absolute spot is that inset and not the
      // bare corner. The distance is what "a fraction of the travel" means.
      final ds = FakePagedBrowserDataSource();

      final topLeft = await barSpotAfter(tester, ds, const Offset(0, 0));
      final page = tester.getSize(find.byType(PaginatedBrowserPage<String>));
      final bar = tester.getSize(find.byType(FloatingGridBar<String>));
      final bottomRight = await barSpotAfter(tester, ds, const Offset(1, 1));

      expect((bottomRight - topLeft).dx, closeTo(page.width - bar.width, 0.5),
          reason: 'the full 0→1 step covers the full width of the travel');
      expect((bottomRight - topLeft).dy, closeTo(page.height - bar.height, 0.5),
          reason: 'the full 0→1 step covers the full height of the travel');
    });

    testWidgets('the centre fraction rests the bar at the centre',
        (tester) async {
      final ds = FakePagedBrowserDataSource();
      final topLeft = await barSpotAfter(tester, ds, const Offset(0, 0));
      await pumpPage(tester, ds, barOffset: const Offset(0.5, 0.5));

      final page = tester.getSize(find.byType(PaginatedBrowserPage<String>));
      final bar = tester.getSize(find.byType(FloatingGridBar<String>));
      final centre = barSpot(tester);

      // The centre sits exactly half the travel from the top-left corner.
      expect(centre.dx - topLeft.dx, closeTo((page.width - bar.width) / 2, 0.5));
      expect(centre.dy - topLeft.dy, closeTo((page.height - bar.height) / 2, 0.5));
    });

    /// Distinct tile rows in the grid, by the top edge of each row.
    int rowCount(WidgetTester tester) {
      final tops = <double>{};
      final tiles = find.byType(FloatingGridTile).evaluate().toList();
      final wide = find.byType(BrowserBarWideTile).evaluate().toList();
      for (final e in [...tiles, ...wide]) {
        final box = e.renderObject! as RenderBox;
        tops.add(box.localToGlobal(Offset.zero).dy);
      }
      return tops.length;
    }

    /// The bar's own block size, i.e. what a user sees.
    Size barBlockSize(WidgetTester tester) =>
        tester.getSize(find.byType(BalancedButtonWrap));

    /// Enters selection mode and returns the controller driving it.
    Future<PaginatedBrowserController<String>> pumpSelection(
      WidgetTester tester,
      FakePagedBrowserDataSource ds, {
      double hostWidth = 400,
    }) async {
      final controller = await pumpPage(
        tester,
        ds,
        size: Size(hostWidth, 640),
      );
      controller.enterSelectionMode(ds.items.first, ds);
      await tester.pumpAndSettle();
      return controller;
    }

    for (final hostWidth in [240.0, 320.0, 430.0, 800.0]) {
      testWidgets('stays 2 rows in BOTH modes at a ${hostWidth.toInt()}px host',
          (tester) async {
        // 430px is the regression that started this: the normal grid is 454px
        // wide and the selection grid 408px, so a 412dp/430pt phone — squarely
        // inside that 46px gap — rendered two rows normally and ONE row in
        // selection, making the bar jump height on entering selection mode.
        // Row count must be decided by the design, not by width division.
        final ds = FakePagedBrowserDataSource(supportsCurrent: true);

        await pumpPage(tester, ds, size: Size(hostWidth, 640));
        expect(rowCount(tester), 2,
            reason: 'normal mode must be 2 rows at ${hostWidth}px');

        final controller = await pumpSelection(tester, ds, hostWidth: hostWidth);
        expect(controller.isSelectionMode, isTrue);
        expect(rowCount(tester), 2,
            reason: 'selection mode must be 2 rows at ${hostWidth}px too');
      });
    }

    testWidgets('both modes render the same block, so the bar never jumps',
        (tester) async {
      // The user-visible symptom: switching to selection changed the bar's
      // height (and width), so the control the finger had just used moved.
      final ds = FakePagedBrowserDataSource(supportsCurrent: true);

      await pumpPage(tester, ds, size: const Size(430, 640));
      final normal = barBlockSize(tester);

      await pumpSelection(tester, ds, hostWidth: 430);
      final selection = barBlockSize(tester);

      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget,
          reason: 'sanity: the bar really did switch to the selection grid');
      expect(selection.height, normal.height,
          reason: 'entering selection must not change the bar height');
      expect(selection.width, normal.width,
          reason: 'entering selection must not change the bar width');
    });

    testWidgets('the locate crosshair is scaled down inside the dense tile',
        (tester) async {
      // `Icons.my_location` is one of Material's visually heaviest glyphs — a
      // crosshair with a solid centre dot — so at the default 24px inside a
      // 40px tile it read as oversized next to the line-art icons beside it.
      final ds = FakePagedBrowserDataSource(supportsCurrent: true);
      await pumpPage(tester, ds);

      final locate = tester.widget<Icon>(find.byIcon(Icons.my_location));
      final sort = tester.widget<Icon>(find.byIcon(Icons.sort_rounded));
      expect(locate.size, lessThan(sort.size ?? 24),
          reason: 'the crosshair must not be the largest glyph in the grid');
    });

    testWidgets('a drag commits ONE fraction at the end of the gesture',
        (tester) async {
      final commits = <Offset>[];
      final ds = FakePagedBrowserDataSource();
      await pumpPage(
        tester,
        ds,
        barOffset: const Offset(0.5, 0.5),
        onBarMoved: commits.add,
      );

      // Press a TILE, not the bar's own box: the bar's layout box stays at the
      // host origin while it is PAINTED at its remembered fraction, so a press
      // aimed at the bar's box would land on the list underneath instead.
      final origin = tester.getCenter(find.byType(FloatingGridTile).first);

      // Start from the centre so there is travel available in every direction.
      final before = barShift(tester);
      final gesture = await tester.startGesture(origin);
      // Several moves: each must move the bar without writing anything.
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(-8, -6));
        await tester.pump();
      }
      expect(commits, isEmpty,
          reason: 'drag frames are memory-only — Drift runs on the UI isolate');

      await gesture.up();
      await tester.pumpAndSettle();

      expect(commits, hasLength(1),
          reason: 'exactly one write per gesture');
      final after = barShift(tester);
      expect(after.dx, lessThan(before.dx),
          reason: 'dragging left must move the bar left');
      expect(after.dy, lessThan(before.dy),
          reason: 'dragging up must move the bar up');
    });

    testWidgets('a drag is clamped to the host, never past it', (tester) async {
      final commits = <Offset>[];
      final ds = FakePagedBrowserDataSource();
      await pumpPage(
        tester,
        ds,
        barOffset: const Offset(0.5, 0.5),
        onBarMoved: commits.add,
      );

      // Press a tile, not the bar's layout box (see the note above).
      final gesture = await tester.startGesture(
          tester.getCenter(find.byType(FloatingGridTile).first));
      // Far more than the host can absorb in either direction.
      for (var i = 0; i < 20; i++) {
        await gesture.moveBy(const Offset(-40, 40));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(commits, hasLength(1));
      final Offset committed = commits.single;
      expect(committed.dx, inInclusiveRange(0.0, 1.0));
      expect(committed.dy, inInclusiveRange(0.0, 1.0));
      expect(committed.dx, 0.0, reason: 'dragged hard left: pinned at 0');
      expect(committed.dy, 1.0, reason: 'dragged hard down: pinned at 1');
    });

    testWidgets('a never-dragged bar commits nothing', (tester) async {
      final commits = <Offset>[];
      final ds = FakePagedBrowserDataSource();
      await pumpPage(tester, ds,
          barOffset: const Offset(0.5, 0.5), onBarMoved: commits.add);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(commits, isEmpty,
          reason: 'a tap is not a drag; the stored spot must stay untouched');
    });

    testWidgets('a tap AFTER a drag still commits nothing', (tester) async {
      // The second gesture is the one that used to slip through: "did this
      // gesture displace the bar" was a flag that was set on the first drag and
      // never cleared, so every LATER tap that lost the arena (reported as
      // onPanCancel — the same callback the drag ends on) committed the spot it
      // never moved. Harmless only because the store drops an equal write.
      final commits = <Offset>[];
      final ds = FakePagedBrowserDataSource();
      await pumpPage(tester, ds,
          barOffset: const Offset(0.5, 0.5), onBarMoved: commits.add);

      final gesture = await tester.startGesture(
          tester.getCenter(find.byType(FloatingGridTile).first));
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(-8, -6));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(commits, hasLength(1), reason: 'sanity: the drag did commit');

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(commits, hasLength(1),
          reason: 'a tap is not a drag, no matter what came before it');
    });

    testWidgets('every control is reachable at the bar\'s PAINTED spot',
        (tester) async {
      // The regression this guards: the bar's layout box stays at the host
      // origin while it paints at its remembered fraction, so a wrapper around
      // the transform bounds-checks against the wrong box and every tap lands on
      // the list instead. It LOOKED correct and was completely dead.
      final ds = FakePagedBrowserDataSource(supportsCurrent: true);
      var closed = 0;
      await tester.pumpWidget(wrap(
        PaginatedBrowserPage<String>(
          dataSource: ds,
          controller: PaginatedBrowserController<String>(),
          onClose: () => closed++,
          showHomePage: false,
          showBackButton: false,
          toolbarLayout: BrowserToolbarLayout.floatingGrid,
          // Parked in the far corner: nothing else is under it there.
          floatingBarOffset: const Offset(1, 1),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(closed, 1, reason: 'close must fire at the painted position');

      await tester.tap(find.byIcon(Icons.navigate_next));
      await tester.pumpAndSettle();
      expect(ds.currentPage, 1,
          reason: 'page navigation must fire at the painted position too');
    });

    testWidgets('an externally changed offset is adopted even after a drag',
        (tester) async {
      // The regression this guards: the bar refused to adopt any external
      // `offset` once the user had dragged it ONCE, so rotating the phone (the
      // queue reads a different per-screen-shape spot) or importing settings
      // silently kept the PREVIOUS shape's position until the page was fully
      // remounted — the desktop spot leaking onto the phone and vice versa.
      final commits = <Offset>[];
      final ds = FakePagedBrowserDataSource();
      final controller = PaginatedBrowserController<String>();

      Future<void> pumpAt(Offset fraction) async {
        await tester.pumpWidget(wrap(
          PaginatedBrowserPage<String>(
            dataSource: ds,
            controller: controller,
            onClose: () {},
            showHomePage: false,
            showBackButton: false,
            toolbarLayout: BrowserToolbarLayout.floatingGrid,
            floatingBarOffset: fraction,
            onFloatingBarMoved: commits.add,
          ),
        ));
        await tester.pumpAndSettle();
      }

      /// The bar's PAINT shift, straight off the transform that applies it.
      /// Read as the TILE's screen spot rather than the matrix, so the probe
      /// needs no vector_math dependency (`getTranslation` returns a Vector3).
      Offset paintShift() => tester.getTopLeft(find.byType(FloatingGridTile).first);

      // Where fraction (0,0) paints: the host's top-left corner plus the bar's
      // own padding, which is the reference the adopted spot must land on.
      await pumpAt(const Offset(0, 0));
      final Offset corner = paintShift();

      await pumpAt(const Offset(0.5, 0.5));
      final centre = paintShift();
      expect(centre.dx, greaterThan(corner.dx),
          reason: 'the centre must differ from the corner, or the probe is blind');

      // Drag it into a corner and commit, exactly as a user would.
      final gesture = await tester.startGesture(
          tester.getCenter(find.byType(FloatingGridTile).first));
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(20, 20));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(commits, hasLength(1));
      expect(paintShift(), isNot(centre), reason: 'the drag must have moved it');

      // Now the host reports a DIFFERENT remembered spot (profile switch /
      // settings import). The bar has been dragged, and must still follow.
      await pumpAt(const Offset(0, 0));
      final Offset adopted = paintShift();
      expect(adopted.dx, closeTo(corner.dx, 0.5));
      expect(adopted.dy, closeTo(corner.dy, 0.5),
          reason: 'fraction (0,0) is the host corner — a dragged bar must '
              'still adopt it, or one screen shape inherits another\'s spot');
    });

    testWidgets('the bar is translucent, not an opaque panel',
        (tester) async {
      final ds = FakePagedBrowserDataSource();
      await pumpPage(tester, ds);

      final material = tester.widget<Material>(
        find.descendant(
          of: find.byType(FloatingGridBar<String>),
          matching: find.byType(Material),
        ).first,
      );
      final Color? color = material.color;
      expect(color, isNotNull);
      expect(color!.a, lessThan(1.0),
          reason: 'V3 floats OVER the list, so it must let it show through');
    });

    testWidgets('the icon tiles are uniform squares, the readouts are 2x',
        (tester) async {
      final ds = FakePagedBrowserDataSource(supportsCurrent: true);
      await pumpPage(tester, ds);

      // sort / prev / next / locate / overflow / close.
      final tiles = find.byType(FloatingGridTile);
      expect(tiles, findsNWidgets(6));
      final sizes = <Size>{
        for (var i = 0; i < tiles.evaluate().length; i++)
          tester.getSize(tiles.at(i)),
      };
      expect(sizes, hasLength(1),
          reason: 'a grid of squares must not mix tile sizes: $sizes');
      expect(sizes.single.width, sizes.single.height);

      // The two number readouts get a double-width plate, so their digits are
      // not shrunk to illegibility to fit a square.
      final wide = find.byType(BrowserBarWideTile);
      expect(wide, findsNWidgets(2), reason: 'page counter + total/per-page');
      final wideSize = tester.getSize(wide.first);
      expect(wideSize.height, sizes.single.height,
          reason: 'a wide tile is still the height of one row');
      expect(wideSize.width, greaterThan(sizes.single.width));
    });
  });
}
