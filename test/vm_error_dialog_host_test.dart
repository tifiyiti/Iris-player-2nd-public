import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/virtual_media/store/vm_playback_store.dart';
import 'package:iris/features/virtual_media/view/vm_error_dialog_host.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
// Test-only StoreLocator host (see pubspec dev_dependencies comment).
import 'package:zustand/zustand.dart';

/// StoreScope-equivalent that does NOT dispose the global StoreLocator on
/// unmount (mirrors frame_tools_float_panel_test.providerScope): a disposing
/// scope would close the store and the next test's replace would throw.
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

void main() {
  setUp(() {
    useVmPlaybackStore().replace(const VmPlaybackState());
  });

  testWidgets(
      'REGRESSION: host stays a Positioned Stack child (no Size.zero collapse)',
      (tester) async {
    // The player Stack is otherwise all-positioned and only sizes via
    // constraints.biggest. A bare non-positioned box here collapses a
    // loose-constrained Stack to Size.zero -> the reported black screen
    // (audio/input keep working). Mirrors frame_tools_float_panel /
    // bg_quick_panel_host.
    await tester.pumpWidget(providerScope(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: Stack(
            key: const ValueKey('host_stack'),
            children: [VmErrorDialogHost(key: UniqueKey())],
          ),
        ),
      ),
    ));
    await tester.pump();

    final size = tester.getSize(find.byKey(const ValueKey('host_stack')));
    expect(size.width, greaterThan(0));
    expect(size.height, greaterThan(0));
  });

  testWidgets('surfaces the stored fatal error as a dialog', (tester) async {
    useVmPlaybackStore()
        .replace(const VmPlaybackState(lastError: 'session-failed'));

    await tester.pumpWidget(providerScope(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Stack(
          children: [VmErrorDialogHost()],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('session-failed'), findsOneWidget);
  });
}
