import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/store/keyboard_form_geometry.dart';
import 'package:iris/utils/platform.dart';
import 'package:iris/widgets/adaptive/keyboard_form_shell.dart';
import 'package:iris/widgets/dialogs/draggable_dialog_shell.dart';

/// Counts how often the form body itself is built. The whole point of the
/// cached-form contract is that neither a drag frame nor a resize frame reaches
/// it, so this is the probe that proves it.
int _formBuilds = 0;

class _CountingForm extends StatelessWidget {
  const _CountingForm();

  @override
  Widget build(BuildContext context) {
    _formBuilds++;
    return KeyboardFormScaffold(
      title: const Text('probe'),
      onClose: () => Navigator.of(context).maybePop(),
      body: const SizedBox(height: 120, child: Text('body')),
      footer: TextButton(
        onPressed: () => Navigator.of(context).pop('done'),
        child: const Text('done'),
      ),
    );
  }
}

Widget _app(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    debugIsMobilePlatformOverride = null;
  });
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => showAdaptiveKeyboardForm<String>(
              context: context,
              form: const _CountingForm(),
              geometry: const KeyboardFormGeometry(),
              onPositionChanged: _positions.add,
              onWidthChanged: _widths.add,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

final List<Offset> _positions = <Offset>[];
final List<double?> _widths = <double?>[];

void main() {
  setUp(() {
    _formBuilds = 0;
    _positions.clear();
    _widths.clear();
  });

  testWidgets('the geometry shell parks the card in the draggable shell',
      (tester) async {
    await tester.pumpWidget(_app(tester, const Size(1280, 800)));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(DraggableDialogShell), findsOneWidget);
    expect(find.byType(Dialog), findsNothing,
        reason: 'the draggable card must shrink-wrap, or the shell measures '
            'the whole screen and the fraction has no travel to divide');
    expect(find.byKey(const ValueKey('keyboard_form_drag_handle')),
        findsOneWidget);
  });

  testWidgets('a pan moves the card, commits one fraction and never rebuilds '
      'the form', (tester) async {
    await tester.pumpWidget(_app(tester, const Size(1280, 800)));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final Offset before = tester.getTopLeft(find.byType(_CountingForm));
    _formBuilds = 0;

    final TestGesture gesture =
        await tester.startGesture(tester.getCenter(
      find.byKey(const ValueKey('keyboard_form_drag_handle')),
    ));
    await gesture.moveBy(const Offset(120, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(120, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(_formBuilds, 0,
        reason: 'a drag is a paint-time transform; the form must not rebuild');
    expect(tester.getTopLeft(find.byType(_CountingForm)).dx,
        greaterThan(before.dx));
    expect(_positions, hasLength(1),
        reason: 'one commit per gesture, not one per frame');
    expect(_positions.single.dx, greaterThan(0.5));
  });

  testWidgets('a landscape phone no longer gets a 560-wide slab',
      (tester) async {
    debugIsMobilePlatformOverride = true;
    await tester.pumpWidget(_app(tester, const Size(914, 411)));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final double width = tester.getSize(find.byType(_CountingForm)).width;
    expect(width, lessThan(kKeyboardFormMaxWidth));
    expect(width, closeTo(411 * kKeyboardFormLandscapeWidthFactor, 1));
  });

  testWidgets('a desktop viewport keeps the 560 cap', (tester) async {
    await tester.pumpWidget(_app(tester, const Size(1280, 800)));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      resolveKeyboardFormWidth(
        viewport: const Size(1280, 800),
        mobile: false,
      ),
      kKeyboardFormMaxWidth,
    );
  });

  testWidgets('the resize grip widens the card, clamps and commits once',
      (tester) async {
    // The landscape phone is where the grip has room to work: its auto width
    // (height-derived) sits well below the M3 ceiling.
    debugIsMobilePlatformOverride = true;
    await tester.pumpWidget(_app(tester, const Size(914, 411)));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final double before = tester.getSize(find.byType(_CountingForm)).width;
    _formBuilds = 0;

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('keyboard_form_resize_grip'))),
    );
    await gesture.moveBy(const Offset(90, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(_formBuilds, 0,
        reason: 'the form instance is passed through, so a width change only '
            'relayouts it');
    expect(tester.getSize(find.byType(_CountingForm)).width,
        closeTo(before + 90, 1));
    expect(_widths, hasLength(1));
    expect(_widths.single, isNotNull);
  });

  testWidgets('the resize grip never pushes the card past the M3 max width',
      (tester) async {
    await tester.pumpWidget(_app(tester, const Size(1280, 800)));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('keyboard_form_resize_grip'))),
    );
    await gesture.moveBy(const Offset(600, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(_CountingForm)).width,
        kKeyboardFormMaxWidth);
    expect(_widths.single, inInclusiveRange(0.0, 1.0));
  });

  testWidgets('the resize grip narrows the card down to the minimum',
      (tester) async {
    await tester.pumpWidget(_app(tester, const Size(1280, 800)));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('keyboard_form_resize_grip'))),
    );
    await gesture.moveBy(const Offset(-4000, 0));
    await tester.pump();
    expect(
      tester.getSize(find.byType(_CountingForm)).width,
      greaterThanOrEqualTo(kKeyboardFormMinWidth - 0.5),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_widths.single, inInclusiveRange(0.0, 1.0));
  });

  testWidgets('without a geometry the shell is unchanged', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAdaptiveKeyboardForm<String>(
                context: context,
                form: const _CountingForm(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(DraggableDialogShell), findsNothing);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byKey(const ValueKey('keyboard_form_drag_handle')), findsNothing);
    expect(find.byKey(const ValueKey('keyboard_form_resize_grip')), findsNothing);
  });

  testWidgets('isDismissible false keeps the parked card open on an outside tap',
      (tester) async {
    // The draggable branch paints its OWN tap-to-pop layer over the scrim, so
    // the route's `barrierDismissible` flag does not reach it. Without the
    // flag being honoured here, a form holding unsaved input that opts out of
    // gesture dismissal still loses that input to a stray click — the exact
    // outcome `isDismissible: false` exists to prevent.
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showAdaptiveKeyboardForm<String>(
                  context: context,
                  form: const _CountingForm(),
                  isDismissible: false,
                  geometry: const KeyboardFormGeometry(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(DraggableDialogShell), findsOneWidget);

    // Top-left corner: scrim, far from both the card and its drag handle.
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.byType(DraggableDialogShell), findsOneWidget);
    expect(find.text('probe'), findsOneWidget);
  });

  testWidgets('isDismissible true still closes the parked card on an outside tap',
      (tester) async {
    // The counterpart, so the fix cannot degenerate into "the scrim never pops".
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showAdaptiveKeyboardForm<String>(
                  context: context,
                  form: const _CountingForm(),
                  geometry: const KeyboardFormGeometry(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.byType(DraggableDialogShell), findsNothing);
  });

  group('per-axis updates', () {
    // The two gestures own ONE axis each, so each update must leave the other
    // alone. A shared `copyWith` cannot express "leave this axis alone" for a
    // nullable field — a null there means BOTH "not passed" and "clear" — which
    // is exactly how a park used to wipe the remembered width.
    test('moving the form keeps the remembered width', () {
      const KeyboardFormGeometry stored = KeyboardFormGeometry(
        offset: Offset(0.5, 0.5),
        widthFraction: 0.42,
      );
      expect(stored.withOffset(const Offset(0.8, 0.2)), const KeyboardFormGeometry(
        offset: Offset(0.8, 0.2),
        widthFraction: 0.42,
      ));
    });

    test('resizing the form keeps the remembered position', () {
      const KeyboardFormGeometry stored = KeyboardFormGeometry(
        offset: Offset(0.8, 0.2),
        widthFraction: 0.42,
      );
      expect(stored.withWidthFraction(0.7), const KeyboardFormGeometry(
        offset: Offset(0.8, 0.2),
        widthFraction: 0.7,
      ));
    });

    test('a null width fraction clears the preference back to auto', () {
      const KeyboardFormGeometry stored = KeyboardFormGeometry(
        offset: Offset(0.3, 0.6),
        widthFraction: 0.42,
      );
      expect(stored.withWidthFraction(null), const KeyboardFormGeometry(
        offset: Offset(0.3, 0.6),
      ));
    });

    test('a move followed by a resize keeps both writes, and the round-trip '
        'survives encode/parse', () {
      // The exact sequence the page-jump prompt performs: park, then widen.
      const KeyboardFormGeometry stored = KeyboardFormGeometry(
        offset: Offset(0.5, 0.5),
        widthFraction: 0.6,
      );
      final KeyboardFormGeometry parked = stored.withOffset(const Offset(0.9, 0.1));
      final KeyboardFormGeometry resized = parked.withWidthFraction(0.3);
      expect(resized.widthFraction, 0.3);
      expect(resized.offset, const Offset(0.9, 0.1));
      expect(KeyboardFormGeometry.parse(resized.encode()), resized);
    });
  });

  group('clamped / parse', () {
    test('a non-finite width degrades to auto, NOT to half the viewport', () {
      // The read path (`sanitizeWidth`) and the write path (`clamped`) must
      // agree on what a corrupt number means, or one bad row renders as a
      // 50%-wide card on write and as auto on read.
      expect(KeyboardFormGeometry.clamped(
        offset: Offset.zero,
        widthFraction: double.nan,
      ).widthFraction, isNull);
      expect(KeyboardFormGeometry.clamped(
        offset: Offset.zero,
        widthFraction: double.infinity,
      ).widthFraction, isNull);
      expect(KeyboardFormGeometry.parse('0.5,0.5,${double.nan}').widthFraction,
          isNull);
      expect(KeyboardFormGeometry.clamped(
        offset: Offset.zero,
        widthFraction: 0.4,
      ).widthFraction, 0.4, reason: 'a real fraction survives');
    });

    test('an out-of-range fraction is clamped, an unparseable row is centred',
        () {
      expect(KeyboardFormGeometry.clamped(
        offset: Offset.zero,
        widthFraction: 5.0,
      ).widthFraction, 1.0);
      final KeyboardFormGeometry junk = KeyboardFormGeometry.parse('a,b');
      expect(junk.offset, const Offset(0.5, 0.5));
      expect(junk.widthFraction, isNull);
    });
  });

  group('resolveKeyboardFormWidth', () {
    test('a stored fraction wins over the auto width', () {
      expect(
        resolveKeyboardFormWidth(
          viewport: const Size(1000, 800),
          mobile: false,
          widthFraction: 0.5,
        ),
        closeTo((1000 - kKeyboardFormDialogGutter * 2) * 0.5, 1),
      );
    });

    test('a fraction below the M3 minimum still yields a usable card', () {
      expect(
        resolveKeyboardFormWidth(
          viewport: const Size(1000, 800),
          mobile: false,
          widthFraction: 0.05,
        ),
        kKeyboardFormMinWidth,
      );
    });

    test('a garbage fraction degrades to the auto width', () {
      expect(
        resolveKeyboardFormWidth(
          viewport: const Size(1000, 800),
          mobile: false,
          widthFraction: double.nan,
        ),
        resolveKeyboardFormWidth(viewport: const Size(1000, 800), mobile: false),
      );
    });

    test('a phone in portrait is not narrowed by the landscape rule', () {
      const Size portrait = Size(700, 1300);
      expect(
        resolveKeyboardFormWidth(viewport: portrait, mobile: true),
        keyboardFormWidthCeiling(portrait),
        reason: 'tall viewports keep the plain ceiling — only a SHORT viewport '
            'is height-derived',
      );
      // Same width, phone turned sideways: now the height rule bites.
      expect(
        resolveKeyboardFormWidth(
          viewport: const Size(914, 411),
          mobile: true,
        ),
        closeTo(411 * kKeyboardFormLandscapeWidthFactor, 1),
      );
    });

    test('a remembered width from a wider screen is clamped down', () {
      // 1280-wide desktop remembers a wide card; the phone it lands on must
      // still fit inside the M3 ceiling.
      expect(
        resolveKeyboardFormWidth(
          viewport: const Size(700, 380),
          mobile: true,
          widthFraction: 1.0,
        ),
        kKeyboardFormMaxWidth,
      );
      expect(
        resolveKeyboardFormWidth(
          viewport: const Size(700, 380),
          mobile: true,
          widthFraction: 1.0,
        ),
        lessThanOrEqualTo(700 - kKeyboardFormDialogGutter * 2 + 0.5),
      );
    });
  });
}
