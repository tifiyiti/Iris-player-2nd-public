import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/settings_transfer/audit/transfer_audit_entry.dart';
import 'package:iris/features/settings_transfer/audit/transfer_audit_store.dart';
import 'package:iris/features/settings_transfer/view/transfer_audit_dialog.dart';
import 'package:iris/l10n/app_localizations.dart';

/// Dual-end guard for the transfer audit dialog: the legacy implementation
/// used a fixed 400x400 box that overflowed a 360px phone. It must now fit
/// the available box (width-constrained + height-clamped to the surface).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      StoreScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showTransferAuditDialog(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('fits a 360x640 phone with a long audit entry (no overflow)',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Seed a worst-case entry directly (load() no-ops before DB init).
    useTransferAuditStore().set([
      TransferAuditEntry(
        at: DateTime(2026, 1, 2, 3, 4, 5),
        op: TransferAuditOp.export,
        sections: const ['App settings', 'Tag play', 'Virtual media'],
        encrypted: true,
        passphraseKind: 'custom',
        result: 'partial',
        note: 'A deliberately long note that must wrap instead of overflowing '
            'the dialog on a narrow phone screen.',
      ),
    ]);

    await openDialog(tester);

    expect(tester.takeException(), isNull,
        reason: 'the audit dialog must not overflow at 360px');
    expect(find.byType(ListTile), findsWidgets);
  });
}
