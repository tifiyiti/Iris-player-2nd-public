import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/scan/view/scan_options_dialog.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/storages/storage.dart';

/// Pumps a host page and opens [ScanOptionsDialog] through a real route.
///
/// [onPopped] receives the dialog's pop value (null = cancelled,
/// false = plain scan, true = probe scan).
Future<void> _openDialog(
  WidgetTester tester, {
  void Function(bool?)? onPopped,
}) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () async {
              final r = await showScanOptionsDialog(context,
                  storageType: StorageType.internal);
              onPopped?.call(r);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));

  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows probe checkbox', (tester) async {
    await _openDialog(tester);

    expect(find.byType(ScanOptionsDialog), findsOneWidget);
    expect(find.text('尝试读取媒体信息（时长 / 分辨率）'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('开始扫描'), findsOneWidget);
  });

  testWidgets('cancel dismisses with null (scan not started)', (tester) async {
    bool? popped;
    await _openDialog(tester, onPopped: (v) => popped = v);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(popped, isNull);
  });

  testWidgets('confirm without toggling starts probe scan (true — default ON)',
      (tester) async {
    bool? popped;
    await _openDialog(tester, onPopped: (v) => popped = v);

    await tester.tap(find.text('开始扫描'));
    await tester.pumpAndSettle();

    expect(popped, isTrue);
  });

  testWidgets('toggling probe off then confirm yields false', (tester) async {
    bool? popped;
    await _openDialog(tester, onPopped: (v) => popped = v);

    // CheckboxListTile toggles when tapping its title — default ON → OFF.
    await tester.tap(find.text('尝试读取媒体信息（时长 / 分辨率）'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('开始扫描'));
    await tester.pumpAndSettle();

    expect(popped, isFalse);
  });
}
