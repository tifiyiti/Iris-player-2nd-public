import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/meta_settings/contributions/settings_catalog.dart';
import 'package:iris/features/meta_settings/model/enum/settings_section.dart';
import 'package:iris/features/meta_settings/view/meta_settings_page.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:drift/native.dart';
import 'package:provider/provider.dart';
import 'package:zustand/zustand.dart';

import 'helpers/sqlite3_loader.dart';

/// Legacy About tab queries package info at build time.
void _mockPackageInfoChannel() {
  const channel = MethodChannel('dev.fluttercommunity.plus/package_info');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          channel,
          (call) async => <String, dynamic>{
                'appName': 'iris',
                'packageName': 'com.test.iris',
                'version': '1.6.0',
                'buildNumber': '6',
              });
}

/// StoreScope-equivalent that does NOT dispose the global StoreLocator on
/// unmount. [StoreScope] tears it down fire-and-forget, which races the next
/// test's store writes (rows silently stop being mirrored / "Cannot add new
/// events after calling close"). Stores here live in that global locator.
Widget _providerScope(Widget child) => InheritedProvider<StoreLocator>.value(
      value: StoreLocator(),
      startListening: (InheritedContext<StoreLocator?> e, StoreLocator value) {
        final sub = value.changes.listen((_) => e.markNeedsNotifyDependents());
        return sub.cancel;
      },
      lazy: false,
      child: child,
    );

Widget _harness() => _providerScope(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 480,
            // Tall enough that lazy ListViews build EVERY row of a section —
            // assertions target rows regardless of their scroll position.
            height: 2800,
            child: MetaSettingsPage(),
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqlite3Loaded();
  _mockPackageInfoChannel();

  // SizedBox heights clamp to the surface's max height, so tests that must
  // reach rows far down a section raise the surface first.
  Future<void> useTallSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(480, 2800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  // DbModule wires late-final singletons → initialize ONCE per file against
  // a single in-memory DB (row isolation across tests is not required here).
  setUpAll(() async {
    final db = AppDatabase(NativeDatabase.memory());
    await DbModule.init(db);
  });

  testWidgets(
      'renders play + general sections from metadata and reuses '
      'legacy about/dependencies tabs', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    // Tab bar mirrors the legacy IA.
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('General'), findsOneWidget);

    // Metadata rows render with localized titles from defs.
    expect(find.text('Media Kit'), findsWidgets); // player_backend enum row
  });

  testWidgets('toggling a boolean row mirrors the change into a DB row',
      (tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    // Switch to the General tab first: TabBarView builds pages lazily.
    await tester.tap(find.text('General').last);
    await tester.pumpAndSettle();

    // The legacy-compat entry hosts the master gate inside its dialog
    // (requirement #5 consolidation).
    final legacyTile = find.text('Legacy compatibility');
    expect(legacyTile, findsOneWidget);
    await tester.ensureVisible(legacyTile);
    await tester.pumpAndSettle();
    await tester.tap(legacyTile);
    await tester.pumpAndSettle();

    // Polarity-agnostic single flip (install default is gate ON → tap turns
    // it OFF). Both mirror contracts are pinned: ON seeds the snapshot, OFF
    // clears it (rollback contract).
    final before = useAppStore().state.useMetadataSettings;
    await tester.tap(find.byKey(const ValueKey('legacy-gate-switch')));
    // Escape fake async so store-notification → rebuild lands on the real
    // event loop, then flush frames.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    final after = useAppStore().state.useMetadataSettings;
    expect(after, !before, reason: 'one tap flips the master gate');

    final rows =
        await tester.runAsync(() => DbModule.metaSettingsRepo.loadRawValues());
    if (after) {
      expect(rows?['app.useMetadataSettings'], 'true',
          reason: 'gate ON mirror-seeds the full state snapshot');
    } else {
      expect(rows?['app.useMetadataSettings'], isNull,
          reason: 'gate OFF clears the mirror (rollback contract)');
    }
  });

  testWidgets('off-screen rows are lazily built (phone perf guard)',
      (tester) async {
    // Regression guard for the lazy ListView.builder: a small phone viewport
    // must not construct the whole (60+ row) Play section.
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_providerScope(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: MetaSettingsPage()),
      ),
    ));
    await tester.pumpAndSettle();

    // A top Play row is built...
    expect(find.byKey(const ValueKey('app.playerBackend')), findsOneWidget);
    // ...while the far tail of the same section is not (lazy build).
    expect(find.byKey(const ValueKey('background_playback.exhaustedAction')),
        findsNothing);
  });

  testWidgets('android-only defs stay hidden on non-android platforms',
      (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    // Tests run on windows host → classic-title-bar row (android-only) hidden,
    // while auto-resize (windows/linux/macos) visible on General tab.
    expect(find.text('use_classic_title_bar'), findsNothing);
  });

  testWidgets(
      'every visible metadata row renders an interactive tile '
      '(no inert placeholders)', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await useTallSurface(tester);
    try {
      final defs = SettingsCatalog.defs;

      Future<void> checkTab(String tabText, SettingsSection section) async {
        await tester.tap(find.text(tabText).last);
        await tester.pumpAndSettle();

        final inert = <String>[];
        for (final d in defs) {
          if (d.section != section) continue;
          if (!MetaSettingsPage.visibleOnCurrentPlatform(d)) continue;

          final rowFinder = find.byKey(ValueKey<String>(d.key));
          // Sections grow with the catalog while the harness viewport stays
          // fixed — scroll each row into view so lazily-built ListView
          // children exist before asserting on them. Target the ACTIVE
          // section's vertical ListView explicitly: the first Scrollable
          // under the TabBarView is its horizontal PageView, which a vertical
          // drag never moves (the test silently relied on everything fitting).
          await tester.scrollUntilVisible(
            rowFinder,
            300,
            scrollable: find
                .descendant(
                  of: find.byType(ListView).hitTestable().first,
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.pumpAndSettle();
          expect(rowFinder, findsOneWidget, reason: '${d.key} must be built');
          final tiles = find.descendant(
            of: rowFinder,
            matching: find
                .byWidgetPredicate((w) => w is ListTile || w is SwitchListTile),
          );
          expect(tiles, findsWidgets, reason: '${d.key} must contain a tile');

          final interactive = tester.widgetList<Widget>(tiles).any((w) =>
                  (w is SwitchListTile && w.onChanged != null) ||
                  (w is ListTile && w.onTap != null)) ||
              // Inline slider rows are interactive without any tile callback.
              find
                  .descendant(of: rowFinder, matching: find.byType(Slider))
                  .evaluate()
                  .isNotEmpty;
          if (!interactive) inert.add(d.key);
        }
        expect(inert, isEmpty,
            reason: 'inert rows mean a missing editor binding or broken '
                'generic renderer');
      }

      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();
      await checkTab('Play', SettingsSection.play);
      await checkTab('General', SettingsSection.general);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('tapping the language bound row opens its legacy dialog',
      (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('General').last);
    await tester.pumpAndSettle();

    final languageRow = find.text('Language');
    expect(languageRow, findsOneWidget);
    // Default language is 'system' → subtitle 'System'; 'English' only exists
    // inside the dialog's radio list, so its appearance proves the dialog
    // opened.
    expect(find.text('English'), findsNothing);

    await tester.ensureVisible(languageRow);
    await tester.pumpAndSettle();
    await tester.tap(languageRow);
    await tester.pumpAndSettle();

    expect(find.text('English'), findsWidgets);
  });

  testWidgets('tapping the switch control itself also mirrors into DB',
      (tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('General').last);
    await tester.pumpAndSettle();

    // Open the legacy-compat dialog and target the gate switch precisely.
    final legacyTile = find.text('Legacy compatibility');
    await tester.ensureVisible(legacyTile);
    await tester.pumpAndSettle();
    await tester.tap(legacyTile);
    await tester.pumpAndSettle();

    final gateSwitch = find.descendant(
      of: find.byKey(const ValueKey('legacy-gate-switch')),
      matching: find.byType(Switch),
    );
    expect(gateSwitch, findsOneWidget);
    final before = useAppStore().state.useMetadataSettings;

    await tester.tap(gateSwitch.first);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    final after = !before;
    expect(useAppStore().state.useMetadataSettings, after);
    if (after) {
      final rows = await tester
          .runAsync(() => DbModule.metaSettingsRepo.loadRawValues());
      expect(rows?['app.useMetadataSettings'], 'true');
    } else {
      // v2 engine contract: disabling the gate CLEARS the mirror (the forced
      // blob write already carried the reverse export).
      expect(
        await tester.runAsync(() => DbModule.metaSettingsRepo.hasAnyValue()),
        isFalse,
      );
    }
  });
}
