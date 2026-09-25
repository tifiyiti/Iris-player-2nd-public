import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/speed/model/enum/speed_rate_picker_mode.dart';
import 'package:iris/features/speed/model/speed_rate_picker_resolver.dart';
import 'package:iris/features/speed/view/rate_wheel_dialog.dart';
import 'package:iris/globals.dart' show rateMenuKeyNotifier;
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/pages/player/control_bar/control_bar_widgets/rate_button.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/platform.dart';
import 'package:iris/widgets/dialogs/show_rate_dialog.dart';

import 'helpers/sqlite3_loader.dart';

/// Dual-wheel speed picker contract:
///
///  * two wheels (whole 0..10 + tenths);
///  * tenths-wheel domain follows the whole wheel — coarse 0 offers [1..9]
///    (no 0.0), coarse 10 offers only [0] (no 10.1+);
///  * a decimal point sits between the wheels and no explanatory copy is
///    rendered — the dial itself teaches the coupling rules;
///  * Save persists the composed speed;
///  * `showRatePickerDialog` dispatches on `speed.rateMode` (dualWheel → wheel,
///    list or gate OFF → the legacy flat dialog).
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

  setUp(() {
    // Widget tests run on a DESKTOP host, and desktop is not offered the wheel
    // at all — without this the default would resolve to the slider.
    debugIsMobilePlatformOverride = true;
    addTearDown(() => debugIsMobilePlatformOverride = null);
  });

  testWidgets('wheels render 0..10 + [0..9] and Save persists', (tester) async {
    await useAppStore().updateRate(1.0);
    await _open(tester, showRateWheelDialog);

    final List<ListWheelScrollView> wheels =
        tester.widgetList<ListWheelScrollView>(find.byType(ListWheelScrollView))
            .toList();
    expect(wheels.length, 2, reason: 'whole-number + tenths wheels');
    expect((wheels[0].childDelegate as dynamic).childCount, 11,
        reason: 'whole wheel spans 0..10');
    expect((wheels[1].childDelegate as dynamic).childCount, 10,
        reason: 'coarse 1 offers [0..9] on the tenths wheel');
    expect(find.text('Playback speed: 1.0X'), findsOneWidget);

    // Whole wheel 1 → 2; title value and save follow.
    await tester.drag(find.byType(ListWheelScrollView).first,
        const Offset(0, -kRateWheelItemExtent));
    await tester.pumpAndSettle();
    expect(find.text('Playback speed: 2.0X'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(useAppStore().state.rate, 2.0,
        reason: 'Save persists the composed speed');
    expect(tester.takeException(), isNull, reason: 'no layout overflow');
  });

  testWidgets('coarse 0 tenths wheel drops 0', (tester) async {
    await useAppStore().updateRate(0.5);
    await _open(tester, showRateWheelDialog);

    final List<ListWheelScrollView> wheels =
        tester.widgetList<ListWheelScrollView>(find.byType(ListWheelScrollView))
            .toList();
    expect((wheels[1].childDelegate as dynamic).childCount, 9,
        reason: 'coarse 0 offers [1..9] on the tenths wheel');
    expect(
      find.descendant(
        of: find.byType(ListWheelScrollView).at(1),
        matching: find.text('0'),
      ),
      findsNothing,
      reason: '0.0 is invalid, so the tenths wheel must not offer 0',
    );
  });

  testWidgets('coarse 10 tenths wheel offers only 0', (tester) async {
    await useAppStore().updateRate(10.0);
    await _open(tester, showRateWheelDialog);

    final List<ListWheelScrollView> wheels =
        tester.widgetList<ListWheelScrollView>(find.byType(ListWheelScrollView))
            .toList();
    expect((wheels[1].childDelegate as dynamic).childCount, 1,
        reason: 'coarse 10 allows only the 10.0 tenths value');
    expect(find.text('Playback speed: 10.0X'), findsOneWidget);
  });

  testWidgets('wheel is a bare dial: decimal point in, explanatory text out',
      (tester) async {
    await useAppStore().updateRate(1.5);
    await _open(tester, showRateWheelDialog);

    // The two wheels read as one number only when a decimal point sits
    // between them.
    expect(find.text('.'), findsOneWidget,
        reason: 'a decimal point bridges the coarse and tenths wheels');
    // No more per-column labels / explanatory sentence: the constraint is
    // learned by spinning the wheel, and every pixel goes to the digits.
    expect(find.text('Integer'), findsNothing);
    expect(find.text('Decimal'), findsNothing);
    expect(find.textContaining('adapts to the integer part'), findsNothing);
    expect(find.byType(ListWheelScrollView), findsNWidgets(2));
  });

  testWidgets('two big wheels fit a 360x640 phone without overflow',
      (tester) async {
    // Space is the whole point of dropping the labels and the caption, so
    // pin the layout to a small portrait phone and assert it stays intact.
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
    });

    await useAppStore().updateRate(3.7);
    await _open(tester, showRateWheelDialog);

    expect(find.byType(ListWheelScrollView), findsNWidgets(2));
    expect(find.text('.'), findsOneWidget);
    expect(find.text('Playback speed: 3.7X'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'no layout overflow');
  });

  testWidgets('default mode opens the wheel; rotation rows round-trip',
      (tester) async {
    await _open(tester, showRatePickerDialog);
    expect(find.byType(ListWheelScrollView), findsNWidgets(2));

    final AppStore store = useAppStore();
    await store.updateSpeedRatePickerMode(SpeedRatePickerMode.list);
    final reapplied = await store.applySpeedRows(store.state);
    expect(reapplied.speedRatePickerMode, SpeedRatePickerMode.list,
        reason: 'speed.rateMode must round-trip through the AUX row');
    expect(
      resolveSpeedRatePickerMode(reapplied, metadataEnabled: true),
      SpeedRatePickerMode.list,
    );
  });

  testWidgets('list mode opens the legacy flat dialog', (tester) async {
    await useAppStore().updateSpeedRatePickerMode(SpeedRatePickerMode.list);
    await _open(tester, showRatePickerDialog);
    expect(find.byType(ListWheelScrollView), findsNothing,
        reason: 'list mode keeps the legacy flat dialog');
    // Rate-independent: the card title is the only text carrying the label.
    expect(find.textContaining('Playback speed'), findsOneWidget);
  });

  testWidgets('gate OFF degrades to the legacy flat dialog', (tester) async {
    await useAppStore().setMetadataGate(false);
    expect(
      resolveSpeedRatePickerMode(useAppStore().state, metadataEnabled: false),
      SpeedRatePickerMode.list,
    );
    await _open(tester, showRatePickerDialog);
    expect(find.byType(ListWheelScrollView), findsNothing);
  });

  testWidgets('RateButton publishes its popup-menu key in BOTH modes',
      (tester) async {
    // Regression: the dualWheel branch used to return early, so the per-mount
    // key was never mounted and `rateMenuKeyNotifier` published a dead key —
    // any keyboard shortcut resolving it via `currentState` would fail.
    await useAppStore().updateRate(1.0);
    await useAppStore()
        .updateSpeedRatePickerMode(SpeedRatePickerMode.dualWheel);

    await tester.pumpWidget(
      StoreScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: RateButton(showControl: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final key = rateMenuKeyNotifier.value;
    expect(key, isNotNull, reason: 'dualWheel must still publish the key');
    expect(key!.currentState, isNotNull,
        reason: 'the published key must resolve to a mounted button');

    // Switching to list mode keeps the same contract.
    await useAppStore().updateSpeedRatePickerMode(SpeedRatePickerMode.list);
    await tester.pumpAndSettle();
    expect(rateMenuKeyNotifier.value?.currentState, isNotNull);
  });
}

Future<void> _open(
    WidgetTester tester, Future<void> Function(BuildContext) opener) async {
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
                onPressed: () => opener(ctx),
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
