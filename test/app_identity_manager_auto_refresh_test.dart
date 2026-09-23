import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/app_identity/model/domain/app_identity_entry.dart';
import 'package:iris/features/app_identity/store/use_app_identity_store.dart';
import 'package:iris/features/app_identity/view/app_identity_manager_page.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:zustand/zustand.dart';

/// StoreScope-equivalent that does NOT dispose the global StoreLocator on
/// unmount (mirrors app_identity_editor_test.providerScope).
Widget providerScope(Widget child) {
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

/// Controllable `queryPinned` fake: records calls, serves staged results.
class FakePinnedQuery {
  FakePinnedQuery(this.staged);

  Set<String> staged;
  int calls = 0;

  Future<Set<String>> call() async {
    calls++;
    return Set.of(staged);
  }
}

AppIdentityEntry entry(String id, String name) => AppIdentityEntry(
      id: id,
      name: name,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );

/// Phone-sized regression for the custom-entry manager page:
/// the pinned badge must track launcher-side changes without reopening,
/// and the active highlight must follow warm-start entry switches while open.
///
/// NOTE on harness: everything (store creation included) must happen inside
/// this single testWidgets body. testWidgets bodies run in a FakeAsync zone
/// while setUp/tearDown run outside it; a zustand store born outside never
/// delivers its broadcast events to in-zone pumps, and deleting a store
/// across zones hangs. Sections below therefore reset store *state* (never
/// the instance) between scenarios. Production is single-zone and unaffected.
void main() {
  testWidgets('manager auto-tracks pinned + active states', (tester) async {
    const surface = Size(360, 700);
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final store = useAppIdentityStore();

    Future<void> resetData() async {
      for (final e in store.state.entries) {
        await store.deleteEntry(e.id);
      }
      await store.setActiveEntry(null);
    }

    Future<void> pump(
      FakePinnedQuery fake, {
      Duration? throttle,
      required String section,
    }) async {
      await tester.pumpWidget(
        providerScope(
          MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              resizeToAvoidBottomInset: false,
              // Distinct key per section: pumpWidget with identical runtime
              // types would otherwise UPDATE the old page (preserving its
              // useState) instead of remounting a fresh one.
              body: AppIdentityManagerPage(
                key: ValueKey('manager-$section'),
                pinnedRefreshThrottle: throttle ?? Duration.zero,
                queryPinned: fake.call,
                isAndroidOverride: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> cycleResume() async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pumpAndSettle();
    }

    // ── 1. mount queries pinned once and renders the badge ──
    await resetData();
    var fake = FakePinnedQuery({'a'});
    await store.upsertEntry(entry('a', 'A'));
    await pump(fake, section: 'mount');
    expect(fake.calls, 1);
    expect(find.text('已固定'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // ── 2. resume re-queries and updates the badge without reopening ──
    await resetData();
    fake = FakePinnedQuery(const {});
    await store.upsertEntry(entry('a', 'A'));
    await pump(fake, section: 'resume');
    expect(find.text('OFF'), findsOneWidget);
    // The user pins the shortcut on the launcher and returns to the app.
    fake.staged = {'a'};
    await cycleResume();
    expect(fake.calls, 2);
    expect(find.text('已固定'), findsOneWidget);
    expect(find.text('OFF'), findsNothing);

    // ── 3. resume inside the throttle window skips the query ──
    await resetData();
    fake = FakePinnedQuery(const {});
    await store.upsertEntry(entry('a', 'A'));
    await pump(fake, throttle: const Duration(seconds: 60), section: 'throttle');
    expect(fake.calls, 1);
    await cycleResume();
    expect(fake.calls, 1,
        reason: 'rapid resume bounces must not hit the Binder channel');

    // ── 4. manual refresh button re-queries ──
    await resetData();
    fake = FakePinnedQuery(const {});
    await store.upsertEntry(entry('a', 'A'));
    await pump(fake, section: 'manual');
    expect(fake.calls, 1);
    fake.staged = {'a'};
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pumpAndSettle();
    expect(fake.calls, 2);
    expect(find.text('已固定'), findsOneWidget);

    // ── 5. editor return refreshes pinned status ──
    await resetData();
    fake = FakePinnedQuery(const {});
    await store.upsertEntry(entry('a', 'A'));
    await pump(fake, section: 'editor');
    expect(fake.calls, 1);
    // Open the editor and close it without changes; the page must still
    // re-query so a launcher-side pin made meanwhile becomes visible.
    fake.staged = {'a'};
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('entryNameField')), findsOneWidget);
    // The editor has no close (X) button; Cancel is the only way to dismiss it.
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(fake.calls, 2);
    expect(find.text('已固定'), findsOneWidget);

    // ── 6. active highlight follows warm-start switches while open ──
    await resetData();
    fake = FakePinnedQuery(const {});
    await store.upsertEntry(entry('a', 'A'));
    await store.upsertEntry(entry('b', 'B'));
    await store.setActiveEntry('a');
    await pump(fake, section: 'highlight');

    Finder cardOf(String name) {
      final icon = find.byIcon(Icons.play_circle_fill_rounded);
      expect(icon, findsOneWidget);
      final card = find.ancestor(of: icon, matching: find.byType(Card));
      return find.descendant(of: card, matching: find.text(name));
    }

    expect(cardOf('A'), findsOneWidget);
    // Warm-start entry launch for B completes while the page stays open.
    await store.setActiveEntry('b');
    await tester.pump();
    await tester.pumpAndSettle();
    expect(cardOf('B'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
