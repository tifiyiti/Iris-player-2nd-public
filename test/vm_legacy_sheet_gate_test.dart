import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/virtual_media/commands/vm_actions.dart';
import 'package:iris/features/virtual_media/view/vm_sheet.dart';
import 'package:iris/features/virtual_media/vm_gate.dart';

void main() {
  test('legacy sheet gate is permanently off (sealed history)', () {
    // The old More-menu control center (VirtualMediaSheet + session card)
    // is sealed history: rule CRUD lives in meta-settings (VmManagerPage)
    // and playback stays unaware single-video. This gate must stay false
    // so the legacy sheet path never executes (no resolve/scan/session work).
    expect(VirtualMediaGate.legacySheetEnabled, isFalse);
  });

  testWidgets('openVirtualMediaSheet is a no-op: no sheet opens',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );
    final context = tester.element(find.byType(Scaffold));
    await openVirtualMediaSheet(context);
    await tester.pumpAndSettle();
    expect(find.byType(VirtualMediaSheet), findsNothing);
  });
}
