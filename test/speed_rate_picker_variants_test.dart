import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/meta_settings/contributions/settings_catalog.dart';
import 'package:iris/features/meta_settings/view/setting_texts.dart';
import 'package:iris/features/speed/model/enum/speed_rate_picker_mode.dart';
import 'package:iris/features/speed/view/rate_picker_card.dart';
import 'package:iris/features/speed/view/rate_preset_chips.dart';
import 'package:iris/features/speed/view/rate_slider_sheet.dart';
import 'package:iris/features/speed/view/rate_wheel_dialog.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/widgets/dialogs/show_rate_dialog.dart';

import 'helpers/sqlite3_loader.dart';

/// Contract for the playback-speed pickers.
///
/// Three shapes, every one of them rendered in the SAME draggable card:
///
///  * `dualWheel` — coupled integer + tenths wheels, previewing live;
///  * `slider`    — segmented-linear track + 3x3 preset grid;
///  * `list`      — legacy flat 0.1 menu, which applies on tap and closes.
///
/// The suite locks the catalog/ARB parity, the per-mode dispatch, the shared
/// card chrome, and the two things the drag must never break: a content drag
/// changes the SPEED (not the position), and a drag writes to storage once per
/// gesture rather than once per frame.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqlite3Loaded();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  setUpAll(() async {
    final db = AppDatabase(NativeDatabase.memory());
    await DbModule.init(db);
  });

  setUp(() async {
    // Both the mode and the remembered card position are AppStore singleton
    // state, so they would otherwise leak from one case into the next.
    await useAppStore()
        .updateSpeedRatePickerMode(SpeedRatePickerMode.dualWheel);
    await useAppStore().updateSpeedRateDialogOffset(
        const AppState().speedRateDialogOffset);
    await useAppStore().updateRate(1.0);
  });

  Finder card() => find.byKey(const ValueKey('rate_picker_card'));
  Finder handle() => find.byKey(const ValueKey('rate_picker_drag_handle'));

  /// The horizontal FRACTION the card is parked at — the quantity the pickers
  /// actually share. Pixels are not comparable across shapes: a 220px wheel
  /// card and a 296px slider card at the same fraction sit at different
  /// centres, because the shift is a share of each card's own travel.
  double xFraction(WidgetTester tester) {
    final Rect r = tester.getRect(card());
    final double screen =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final double span = screen - r.width;
    return 0.5 + (r.left - span / 2) / span;
  }

  group('rateMode catalog parity', () {
    test('the catalog advertises exactly the enum values', () {
      final def = SettingsCatalog.defs
          .firstWhere((d) => d.key == 'speed.rateMode', orElse: () {
        fail('speed.rateMode must stay in the settings catalog');
      });
      expect(
        def.enumValues,
        SpeedRatePickerMode.values.map((m) => m.name).toList(),
        reason: 'a mode missing from enumValues is unselectable in the UI',
      );
      expect(def.defaultValue, isIn(def.enumValues),
          reason: 'settings_contribution_test rejects an out-of-set default');
    });

    test('every value has a real label in en AND zh', () async {
      final AppLocalizations en =
          await AppLocalizations.delegate.load(const Locale('en'));
      final AppLocalizations zh =
          await AppLocalizations.delegate.load(const Locale('zh'));
      for (final SpeedRatePickerMode mode in SpeedRatePickerMode.values) {
        expect(SettingTexts.enumLabel('speed.rateMode', mode.name, en),
            isNot(mode.name),
            reason: '${mode.name} has no English label');
        expect(SettingTexts.enumLabel('speed.rateMode', mode.name, zh),
            isNot(mode.name),
            reason: '${mode.name} falls back to the raw name in Chinese');
      }
    });
  });

  group('dispatch', () {
    for (final SpeedRatePickerMode mode in SpeedRatePickerMode.values) {
      testWidgets('mode ${mode.name} opens its own picker', (tester) async {
        await _openAs(tester, mode);

        expect(_expected(mode), findsOneWidget,
            reason: '${mode.name} must not fall through to another picker');
        expect(tester.takeException(), isNull,
            reason: '${mode.name} must lay out without overflow');
      });
    }
  });

  group('shared card chrome', () {
    testWidgets('wheel and slider offer Cancel + Save', (tester) async {
      for (final SpeedRatePickerMode mode in <SpeedRatePickerMode>[
        SpeedRatePickerMode.dualWheel,
        SpeedRatePickerMode.slider,
      ]) {
        await _openAs(tester, mode);
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.text('Save'), findsOneWidget);
        await _close(tester);
      }
    });

    testWidgets('the flat list applies on tap, so it offers Cancel alone',
        (tester) async {
      await _openAs(tester, SpeedRatePickerMode.list);
      expect(find.text('Save'), findsNothing,
          reason: 'a tap already applies; a Save step would be a second tap');
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('Cancel rolls the live preview back to the opening rate',
        (tester) async {
      await useAppStore().updateRate(1.5);
      await _openAs(tester, SpeedRatePickerMode.slider);

      await tester.drag(find.byType(Slider), const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(useAppStore().state.rate, isNot(1.5),
          reason: 'dragging must preview live so the speed can be heard');

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(useAppStore().state.rate, 1.5,
          reason: 'Cancel restores the rate the card opened with');
    });

    testWidgets('Save commits the previewed rate', (tester) async {
      await _openAs(tester, SpeedRatePickerMode.slider);

      await tester.drag(find.byType(Slider), const Offset(60, 0));
      await tester.pumpAndSettle();
      final double previewed = useAppStore().state.rate;
      expect(previewed, isNot(1.0));

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(useAppStore().state.rate, previewed,
          reason: 'Save keeps whatever the preview settled on');
    });

    testWidgets('a tap in the flat list applies and closes', (tester) async {
      await _openAs(tester, SpeedRatePickerMode.list);

      await tester.tap(find.text('0.1X'));
      await tester.pumpAndSettle();

      expect(useAppStore().state.rate, 0.1);
      expect(card(), findsNothing, reason: 'the tap closes the picker');
    });
  });

  group('preset grid', () {
    testWidgets('nine presets lay out as an exact 3x3 grid', (tester) async {
      await _openAs(tester, SpeedRatePickerMode.slider);

      final Finder chips = find.byType(ChoiceChip);
      expect(chips, findsNWidgets(kRatePresetStops.length));
      expect(kRatePresetStops.length, 9, reason: 'the grid is 3x3 by design');

      final List<double> rows = <double>[
        for (int i = 0; i < kRatePresetStops.length; i++)
          tester.getCenter(chips.at(i)).dy.roundToDouble(),
      ];
      final Set<double> distinct = rows.toSet();
      expect(distinct.length, 3, reason: 'nine chips must form three rows');
      for (final double y in distinct) {
        expect(rows.where((double v) => v == y).length, kRatePresetColumns,
            reason: 'every row must hold exactly three chips');
      }
    });

    testWidgets('every preset chip is the same size', (tester) async {
      _phoneViewport(tester);
      // A user who has turned the system font up is the case that breaks a
      // label-sized chip: "0.25X" outgrows its cell while "3.0X" does not, and
      // the grid stops reading as a grid.
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await _openAs(tester, SpeedRatePickerMode.slider);

      final Finder chips = find.byType(ChoiceChip);
      expect(chips, findsNWidgets(kRatePresetStops.length));
      final Rect first = tester.getRect(chips.at(0));
      for (int i = 0; i < kRatePresetStops.length; i++) {
        final Rect r = tester.getRect(chips.at(i));
        expect(r.width, closeTo(first.width, 0.01));
        expect(r.height, closeTo(first.height, 0.01));
        final Rect label = tester.getRect(
            find.descendant(of: chips.at(i), matching: find.byType(Text)));
        expect(label.center.dx, closeTo(r.center.dx, 0.5),
            reason: 'chip $i label is off-centre (label=$label, chip=$r)');
        expect(label.center.dy, closeTo(r.center.dy, 0.5),
            reason: 'chip $i label is off-centre (label=$label, chip=$r)');
        expect(label.width, lessThanOrEqualTo(r.width),
            reason: 'chip $i label outgrew its cell ($label in $r)');
      }
      expect(tester.takeException(), isNull,
          reason: 'a large font scale must not overflow the grid');
    });

    testWidgets('the grid reaches 3.0 and applies off-grid presets exactly',
        (tester) async {
      await _openAs(tester, SpeedRatePickerMode.slider);

      Finder chip(String label) => find.descendant(
            of: find.byType(RatePresetChips),
            matching: find.text(label),
          );

      expect(chip('3.0X'), findsOneWidget, reason: '3.0 completes the 3x3');

      // 0.75 is deliberately off the 0.1 grid the wheels/list share: the chip
      // must apply it exactly rather than rounding to 0.8.
      await tester.tap(chip('0.75X'));
      await tester.pumpAndSettle();
      expect(useAppStore().state.rate, 0.75);

      await tester.tap(chip('3.0X'));
      await tester.pumpAndSettle();
      expect(useAppStore().state.rate, 3.0);
    });
  });

  testWidgets('the wheel selection band is inset, not a full-bleed slab',
      (tester) async {
    await _openAs(tester, SpeedRatePickerMode.dualWheel);

    final Rect band = tester.getRect(find.byKey(const ValueKey('rate_wheel_band')));
    final Rect coarse = tester.getRect(find.byType(ListWheelScrollView).first);
    final Rect fine = tester.getRect(find.byType(ListWheelScrollView).last);

    // Insetting is what keeps the dial from reading as a heavy bar; the band
    // still spans both wheels, so `1 . 5` stays one number.
    expect(band.left - coarse.left, closeTo(kRateWheelBandInset, 0.5));
    expect(fine.right - band.right, closeTo(kRateWheelBandInset, 0.5));
  });

  group('dragging the card', () {
    testWidgets('the handle moves the card', (tester) async {
      await _openAs(tester, SpeedRatePickerMode.slider);
      final Offset before = tester.getCenter(card());

      await tester.drag(handle(), const Offset(70, 50));
      await tester.pumpAndSettle();

      final Offset after = tester.getCenter(card());
      expect(after.dx, greaterThan(before.dx + 10));
      expect(after.dy, greaterThan(before.dy + 5));
    });

    testWidgets('dragging the CONTENT changes the speed, never the position',
        (tester) async {
      await _openAs(tester, SpeedRatePickerMode.slider);
      final Offset before = tester.getCenter(card());
      final double rateBefore = useAppStore().state.rate;

      await tester.drag(find.byType(Slider), const Offset(60, 0));
      await tester.pumpAndSettle();

      expect(tester.getCenter(card()), before,
          reason: 'a content drag must not be stolen by the move gesture');
      expect(useAppStore().state.rate, isNot(rateBefore));
    });

    testWidgets('drag frames stay memory-only; one commit per gesture',
        (tester) async {
      await _openAs(tester, SpeedRatePickerMode.slider);
      final Offset stored = useAppStore().state.speedRateDialogOffset;

      final TestGesture gesture =
          await tester.startGesture(tester.getCenter(handle()));
      await gesture.moveBy(const Offset(70, 0));
      await tester.pump();
      expect(useAppStore().state.speedRateDialogOffset, stored,
          reason: 'a per-frame write would hit Drift on the UI isolate');

      await gesture.up();
      await tester.pumpAndSettle();
      expect(useAppStore().state.speedRateDialogOffset, isNot(stored),
          reason: 'the gesture must persist once it ends');
    });

    testWidgets('the parked spot comes back the next time it opens',
        (tester) async {
      await _openAs(tester, SpeedRatePickerMode.slider);
      await tester.drag(handle(), const Offset(80, 60));
      await tester.pumpAndSettle();
      final double parked = xFraction(tester);
      await _close(tester);

      await _openAs(tester, SpeedRatePickerMode.slider);
      expect(xFraction(tester), closeTo(parked, 0.01));
    });

    testWidgets('the position is shared by every picker shape', (tester) async {
      await _openAs(tester, SpeedRatePickerMode.slider);
      await tester.drag(handle(), const Offset(80, 0));
      await tester.pumpAndSettle();
      final double parked = xFraction(tester);
      await _close(tester);

      await _openAs(tester, SpeedRatePickerMode.dualWheel);
      expect(xFraction(tester), closeTo(parked, 0.01),
          reason: 'one remembered spot serves whichever picker is current');
    });
  });

  group('card size on a phone', () {
    testWidgets('the card is inset from the screen edges', (tester) async {
      _phoneViewport(tester);
      for (final SpeedRatePickerMode mode in SpeedRatePickerMode.values) {
        await _openAs(tester, mode);
        final Rect r = tester.getRect(card());
        // The card stretches to its constraint, so without an explicit side
        // margin it runs edge to edge and stops reading as a dialog.
        expect(r.left, greaterThanOrEqualTo(24),
            reason: '${mode.name} runs into the left edge (left=${r.left})');
        expect(r.right, lessThanOrEqualTo(360 - 24),
            reason: '${mode.name} runs into the right edge (right=${r.right})');
        await _close(tester);
      }
    });

    testWidgets('the slider card stays compact on a phone', (tester) async {
      _phoneViewport(tester);
      await _openAs(tester, SpeedRatePickerMode.slider);
      final Rect r = tester.getRect(card());
      // Measured 312 on a 640px screen. The bound is loose enough not to flake
      // on font metrics but tight enough to catch the regression it guards.
      expect(r.height, lessThanOrEqualTo(640 * 0.52),
          reason: 'the slider card is ${r.height}px on a 640px screen');
      await _close(tester);
    });

    testWidgets('no card exceeds the height cap', (tester) async {
      _phoneViewport(tester);
      for (final SpeedRatePickerMode mode in SpeedRatePickerMode.values) {
        await _openAs(tester, mode);
        final Rect r = tester.getRect(card());
        expect(r.height, lessThanOrEqualTo(640 * 0.61),
            reason: '${mode.name} card is ${r.height}px on a 640px screen');
        await _close(tester);
      }
    });

    testWidgets('the wheel card action row never overflows', (tester) async {
      _phoneViewport(tester);
      await _openAs(tester, SpeedRatePickerMode.dualWheel);

      // The narrowed card can be too tight for two action labels in a long
      // locale (German needs ~210px of the 180 available at 220 wide), so the
      // row is a Wrap: a second row is acceptable, an overflow is not.
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(tester.takeException(), isNull,
          reason: 'the action row must wrap, never overflow');
      await _close(tester);
    });

    testWidgets('the wheel card is narrower than the slider card',
        (tester) async {
      _phoneViewport(tester);

      await _openAs(tester, SpeedRatePickerMode.dualWheel);
      final double wheelWidth = tester.getRect(card()).width;
      await _close(tester);

      await _openAs(tester, SpeedRatePickerMode.slider);
      final double sliderWidth = tester.getRect(card()).width;

      expect(wheelWidth, lessThanOrEqualTo(kRateWheelCardMaxWidth + 0.5),
          reason: 'the wheel card came out $wheelWidth wide');
      expect(wheelWidth, lessThan(sliderWidth),
          reason: 'a wheel column holds one digit; it must not get slider room');
    });
  });

  testWidgets('the card surface is translucent over the video', (tester) async {
    await _openAs(tester, SpeedRatePickerMode.slider);

    final Material surface = tester.widget<Material>(card());
    expect(surface.color, isNotNull);
    // An opaque card reads as a slab pasted over live video, so the opacity is
    // pinned rather than left to drift back.
    expect(surface.color!.a, closeTo(kRateCardSurfaceOpacity, 1e-6));
    expect(surface.color!.a, lessThan(1.0));
  });

  testWidgets('every picker fits a 360x640 phone', (tester) async {
    _phoneViewport(tester);

    for (final SpeedRatePickerMode mode in SpeedRatePickerMode.values) {
      await _openAs(tester, mode);
      expect(tester.takeException(), isNull,
          reason: '${mode.name} overflows a small portrait phone');
      await _close(tester);
    }
  });
}

/// Pins the surface to a small portrait phone for the rest of the case.
void _phoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetViewInsets();
  });
}

Finder _expected(SpeedRatePickerMode mode) => switch (mode) {
      SpeedRatePickerMode.dualWheel => find.byType(RateWheelDialog),
      SpeedRatePickerMode.slider => find.byType(RateSliderSheet),
      SpeedRatePickerMode.list => find.byType(RateDialog),
    };

Future<void> _openAs(WidgetTester tester, SpeedRatePickerMode mode) async {
  await useAppStore().updateSpeedRatePickerMode(mode);
  await tester.pumpWidget(
    StoreScope(
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (BuildContext ctx) => Center(
              child: FilledButton(
                onPressed: () => showRatePickerDialog(ctx),
                child: const Text('OPEN'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('OPEN'));
  await tester.pumpAndSettle();
}

Future<void> _close(WidgetTester tester) async {
  if (find.text('Cancel').evaluate().isNotEmpty) {
    await tester.tap(find.text('Cancel'));
  } else {
    await tester.tapAt(const Offset(4, 4));
  }
  await tester.pumpAndSettle();
}
