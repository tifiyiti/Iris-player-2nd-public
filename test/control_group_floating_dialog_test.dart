import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/control_group/store/use_control_group_store.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/widgets/dialogs/show_control_group_floating_dialog.dart';
import 'package:provider/provider.dart';
import 'package:zustand/zustand.dart';

Widget _providerScope(Widget child) => InheritedProvider<StoreLocator>.value(
      value: StoreLocator(),
      startListening: (InheritedContext<StoreLocator?> e, StoreLocator value) {
        final sub = value.changes.listen((_) => e.markNeedsNotifyDependents());
        return sub.cancel;
      },
      lazy: false,
      child: child,
    );

Widget _harness(Widget child) => _providerScope(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ch = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(ch, (call) async => null);

  tearDown(() {
    StoreLocator().delete(ControlGroupStore);
  });

  testWidgets('exposes two orientation switches and commits each live',
      (tester) async {
    final store = useControlGroupStore();
    await store.initialized;
    store.set(store.state.copyWith(
      floatingButtonPortrait: true,
      floatingButtonLandscape: false,
    ));

    await tester.pumpWidget(_harness(const ControlGroupFloatingDialog()));
    await tester.pumpAndSettle();

    expect(find.byType(SwitchListTile), findsNWidgets(2));
    expect(find.text('Show in landscape'), findsOneWidget);
    expect(find.text('Show in portrait'), findsOneWidget);

    // Toggle landscape ON and portrait OFF.
    await tester.tap(find.text('Show in landscape'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show in portrait'));
    await tester.pumpAndSettle();

    expect(store.state.floatingButtonLandscape, isTrue);
    expect(store.state.floatingButtonPortrait, isFalse);
  });
}
