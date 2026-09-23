import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/osd/engine/osd_texts.dart';
import 'package:iris/features/osd/model/osd_entry.dart';
import 'package:iris/features/osd/store/osd_store.dart';
import 'package:iris/features/osd/view/osd_overlay.dart';
import 'package:iris/l10n/app_localizations_en.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:provider/provider.dart';
import 'package:zustand/zustand.dart';

/// Regression for the double-Positioned.fill crash (windows_play log
/// "Incorrect use of ParentDataWidget — IgnorePointer ← Positioned ←
/// OsdOverlay ← Positioned ← Stack"). The fix keeps the outer wrapper
/// in Player (Positioned.fill) and makes OsdOverlay return bare
/// IgnorePointer/Align (no inner Positioned.fill).

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

Widget _harness(Widget child) => _providerScope(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: child,
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  setUpAll(() async {
    await DbModule.init(AppDatabase(NativeDatabase.memory()));
    // Gate ON so the overlay actually renders the pill.
    useAppStore().set(
      useAppStore().state.copyWith(
            useMetadataSettings: true,
            osdEnabled: true,
          ),
    );
  });

  // Keep the global StoreLocator alive across tests (providerScope) so
  // hide()/show() after widget disposal doesn't hit "disposed store".
  setUp(() {
    useOsdStore().hide();
  });

  testWidgets('no ParentDataWidget assertion when shown inside Positioned.fill',
      (tester) async {
    // Store must be set BEFORE pump (FakeAsync select quirk noted in
    // frame_tools_float_panel_test).
    useOsdStore().show(OsdTexts.volume(42, AppLocalizationsEn()));
    await tester.pumpWidget(
      _harness(
        Stack(
          children: [
            // Mirrors Player's mount point: the overlay is wrapped externally.
            Positioned.fill(child: OsdOverlay(key: UniqueKey())),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull,
        reason: 'OsdOverlay must not double-write StackParentData');
    expect(find.text('Volume'), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
    // Cancel the pending hide timer so the test harness sees no pending timers.
    useOsdStore().hide();
    await tester.pump();
  });

  testWidgets('returns SizedBox.shrink when entry is null (no crash)',
      (tester) async {
    useOsdStore().hide();
    await tester.pumpWidget(
      _harness(
        Stack(
          children: [Positioned.fill(child: OsdOverlay(key: UniqueKey()))],
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    // No pill text when hidden.
    expect(find.text('Volume'), findsNothing);
  });

  testWidgets('does not throw under any gate state', (tester) async {
    useOsdStore().show(const OsdEntry(line1: 'Seek -00:05', line2: '00:10'));
    await tester.pumpWidget(
      _harness(
        Stack(
          children: [Positioned.fill(child: OsdOverlay(key: UniqueKey()))],
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    useOsdStore().hide();
    await tester.pump();
  });
}
