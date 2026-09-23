import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/utils/portable_import.dart';
import 'package:iris/widgets/dialogs/show_data_storage_info_dialog.dart';
import 'package:iris/widgets/dialogs/show_portable_import_dialog.dart';

// NOTE: zh cases live in their own file. flutter test's fake async cannot
// reliably load a SECOND deferred l10n chunk after an en test already ran in
// the same file (tree rebuilds to empty and pumpAndSettle returns early).
// One locale per file avoids the cross-test locale-switch stall entirely.
Future<void> _pumpZhDialogOpener(
  WidgetTester tester,
  Future<dynamic> Function(BuildContext) open,
) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => open(context),
            child: const Text('OPEN'),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OPEN'));
  await tester.pumpAndSettle();
}

void main() {
  group('storageInfoSections zh', () {
    testWidgets('zh layout renders localized sections', (tester) async {
      late List<StorageInfoSection> sections;
      await _pumpZhDialogOpener(tester, (ctx) async {
        sections =
            storageInfoSections(windows: false, t: AppLocalizations.of(ctx)!);
      });
      final text = sections.map((s) => '${s.header}\n${s.body}').join('\n');

      expect(text, contains('应用私有'));
      expect(text, contains('卸载'));
      expect(text, contains('重新输入'));
      expect(text, contains('明文'));
    });
  });

  group('DataStorageInfoDialog zh', () {
    testWidgets('zh dialog renders localized title and sections',
        (tester) async {
      await _pumpZhDialogOpener(tester, showDataStorageInfoDialog);

      expect(find.text('数据与密码存储说明'), findsOneWidget);
      expect(find.text('知道了'), findsOneWidget);
      expect(find.textContaining('明文'), findsWidgets);
    });
  });

  group('PortableImportDialog zh', () {
    testWidgets('zh dialog renders localized actions', (tester) async {
      const scan =
          PortableImportScanResult(legacyDbExists: true, migratableKvCount: 2);
      await _pumpZhDialogOpener(tester, (ctx) async {
        await showPortableImportDialog(ctx, scan: scan);
      });

      expect(find.text('发现已安装版数据'), findsOneWidget);
      expect(find.text('跳过'), findsOneWidget);
      expect(find.text('导入'), findsOneWidget);
      expect(find.textContaining('媒体库数据库'), findsOneWidget);
    });
  });
}
