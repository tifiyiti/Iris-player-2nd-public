import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/widgets/dialogs/show_snake_fine_window_dialog.dart';

import 'helpers/sqlite3_loader.dart';

/// Fine-tune range dialog contract (5–600 s):
///
///  * store-level clamp — every write lands inside [5, 600];
///  * minutes wheel spans 0–10 (11 items);
///  * at 0 minutes the seconds wheel offers [5, 10 .. 55] (11 items) so the
///    smallest reachable value is exactly 5 s — never 0;
///  * Save persists the composed value.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqlite3Loaded();

  // Secure-storage platform channel has no plugin under test — without a
  // mock reply the awaited blob write inside AppStore._persist never
  // completes and the test isolate hangs.
  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  // AppStore.onReady chains into storage/play-queue backends; without the
  // DB module the first persisting mutator hangs the test isolate.
  setUpAll(() async {
    final db = AppDatabase(NativeDatabase.memory());
    await DbModule.init(db);
  });

  testWidgets('fine-tune range: 5 s floor, 0–10 min wheels, save', (tester) async {
    // ── Store-level clamp contract ──
    await useAppStore().updateSnakeFineWindowSeconds(3);
    expect(useAppStore().state.snakeFineWindowSeconds, 5,
        reason: 'values below 5 clamp up to 5');
    await useAppStore().updateSnakeFineWindowSeconds(1000);
    expect(useAppStore().state.snakeFineWindowSeconds, 600,
        reason: 'values above 600 clamp down to 600');
    await useAppStore().updateSnakeFineWindowSeconds(5);
    expect(useAppStore().state.snakeFineWindowSeconds, 5);
    await useAppStore().updateSnakeFineWindowSeconds(600);
    expect(useAppStore().state.snakeFineWindowSeconds, 600);

    // ── Dialog at 30 s ──
    await useAppStore().updateSnakeFineWindowSeconds(30);
    await _open(tester);
    expect(find.text('Fine tune range'), findsOneWidget);

    final List<ListWheelScrollView> wheels =
        tester.widgetList<ListWheelScrollView>(find.byType(ListWheelScrollView))
            .toList();
    expect(wheels.length, 2, reason: 'minutes + seconds wheels');

    final dynamic minDelegate = wheels[0].childDelegate;
    expect(minDelegate.childCount, 11,
        reason: 'minutes wheel spans 0..10 inclusive');

    expect(find.textContaining('±30s'), findsOneWidget,
        reason: 'preview mirrors the stored value');

    // Minutes 0 → 1 moves the preview to ±90s.
    await tester.drag(find.byType(ListWheelScrollView).first,
        const Offset(0, -32));
    await tester.pumpAndSettle();
    expect(find.textContaining('±90s'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(useAppStore().state.snakeFineWindowSeconds, 90,
        reason: 'Save persists the composed value');

    // ── Dialog at 5 s: seconds wheel must floor at 5 (no 0 option) ──
    await useAppStore().updateSnakeFineWindowSeconds(5);
    await _open(tester);
    final List<ListWheelScrollView> wheels2 =
        tester.widgetList<ListWheelScrollView>(find.byType(ListWheelScrollView))
            .toList();
    final dynamic secDelegate = wheels2[1].childDelegate;
    expect(secDelegate.childCount, 11,
        reason: 'at 0 minutes the seconds subset is [5,10..55] (11 items)');
    expect(
      find.descendant(
        of: find.byType(ListWheelScrollView).at(1),
        matching: find.text('0'),
      ),
      findsNothing,
      reason: 'the 0-minute seconds wheel must not offer 0 s',
    );
  });
}

Future<void> _open(WidgetTester tester) async {
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
                onPressed: () => showSnakeFineWindowDialog(ctx),
                child: const Text('OPEN'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  // Deferred l10n delegates load async — settle before tapping.
  await tester.pumpAndSettle();
  await tester.tap(find.text('OPEN'));
  await tester.pumpAndSettle();
}
