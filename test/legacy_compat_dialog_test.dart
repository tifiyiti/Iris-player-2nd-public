import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/widgets/dialogs/show_legacy_compat_dialog.dart';
// Test-only StoreLocator host (see pubspec dev_dependencies comment).
import 'package:zustand/zustand.dart';
import 'package:provider/provider.dart';

/// Requirement #5 (legacy 收拢): one dialog hosts the master gate, the
/// dual-write policy and the three legacy runtime toggles; syncLegacyBlob is
/// inert while the gate is OFF (blob is authoritative then).
void main() {
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

  Future<void> pumpDialog(WidgetTester tester) async {
    await tester.pumpWidget(providerScope(const MaterialApp(
      locale: Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: LegacyCompatDialog()),
    )));
    await tester.pumpAndSettle();
  }

  testWidgets('renders all five legacy toggles', (tester) async {
    await pumpDialog(tester);

    expect(find.byKey(const ValueKey('legacy-gate-switch')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('legacy-sync-blob-switch')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('legacy-title-bar-switch')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('legacy-control-bar-switch')), findsOneWidget);
    expect(find.byKey(const ValueKey('legacy-storage-switch')), findsOneWidget);
  });

  testWidgets('master gate toggle flips useMetadataSettings live',
      (tester) async {
    final store = useAppStore();
    store.set(store.state.copyWith(useMetadataSettings: true));
    await pumpDialog(tester);

    await tester.tap(find.byKey(const ValueKey('legacy-gate-switch')));
    await tester.pump();

    expect(store.state.useMetadataSettings, isFalse);
  });

  testWidgets('syncLegacyBlob is inert while the gate is OFF',
      (tester) async {
    final store = useAppStore();
    store.set(store.state.copyWith(useMetadataSettings: false));
    await pumpDialog(tester);

    final switchWidget = tester.widget<Switch>(
      find.descendant(
        of: find.byKey(const ValueKey('legacy-sync-blob-switch')),
        matching: find.byType(Switch),
      ),
    );
    expect(switchWidget.onChanged, isNull,
        reason: 'dual-write knob must be greyed out (never interactable) '
            'while the master gate is off');
  });
}
