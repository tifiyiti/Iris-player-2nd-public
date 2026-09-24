import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/virtual_media/commands/vm_actions.dart';
import 'package:iris/features/virtual_media/model/enum/vm_enums.dart';
import 'package:iris/features/virtual_media/view/vm_rule_editor_v2.dart';
import 'package:iris/l10n/app_localizations.dart';

// The media-browser "Add as virtual merge" quick-add builds folder-scoped
// defaults (storage+folder name, recursive specified dir) and the V2 editor
// prefills from them.
void main() {
  group('folderVmRuleDefaults', () {
    test('names storage + folder and picks recursive specified dir', () {
      final d = folderVmRuleDefaults(
        storageName: 'E',
        folderName: 'Anime',
        folderPath: 'Anime',
      );
      expect(d.name, 'E - Anime');
      expect(d.matchMode, VmMatchMode.specifiedDirRecursive);
      expect(d.paths, ['Anime']);
    });

    test('a storage root falls back to the storage name', () {
      final d = folderVmRuleDefaults(
        storageName: 'E',
        folderName: '',
        folderPath: '',
      );
      expect(d.name, 'E');
      expect(d.paths, ['']);
    });
  });

  testWidgets('editor prefills a folder draft', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(
        body: VmRuleEditorV2Dialog(
          defaultName: 'E - Anime',
          defaultMatchMode: VmMatchMode.specifiedDirRecursive,
          defaultPaths: ['Anime'],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('E - Anime'), findsOneWidget);
    expect(find.text('Anime'), findsOneWidget);
    expect(find.text('指定目录（递归）'), findsOneWidget);
  });
}
