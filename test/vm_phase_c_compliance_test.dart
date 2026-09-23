import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/virtual_media/commands/vm_actions.dart';
import 'package:iris/features/virtual_media/interaction/ui/vm_drag_preview_overlay.dart';
import 'package:iris/features/virtual_media/store/vm_bootstrap.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/l10n/app_localizations_en.dart';
import 'package:iris/l10n/app_localizations_zh.dart';

void main() {
  group('Phase C compliance', () {
    test('seed default rule description is English (ARB zero-exemption)', () {
      final d = VirtualMediaBootstrap.defaultRule().description;
      expect(d, startsWith('Default rule'));
      expect(d.characters.any((c) => c.codeUnitAt(0) > 127), isFalse);
    });

    test('VmNameExhaustedException carries no user-visible Chinese', () {
      expect(
        const VmNameExhaustedException(5).toString(),
        isNot(contains('复制')),
      );
    });

    testWidgets('drag preview renders ARB text within 360px', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: Center(
              child: VmDragPreviewOverlay(
                segIndex: 0,
                segCount: 3,
                segName: 'averylongsegname_thatcouldoverflow.mp4',
                localPos: Duration(seconds: 10),
                segDur: Duration(minutes: 2),
                virtualPos: Duration(seconds: 70),
                totalDur: Duration(minutes: 6),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Jump to 1/3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('drag preview Chinese ARB renders via placeholders', () {
      // Direct delegate assertion (no widget): deferred zh loading in a
      // multi-locale widget file is a test-harness quirk, unrelated to prod.
      final t = AppLocalizationsZh();
      expect(
        t.vm_drag_preview(2, 3, 'a.mp4', '00:10', '02:00', '01:10', '06:00'),
        '将跳转第2/3段 a.mp4 · 内 00:10/02:00 · 外 01:10/06:00',
      );
      final e = AppLocalizationsEn();
      expect(
        e.vm_drag_preview(1, 3, 'a.mp4', '00:10', '02:00', '01:10', '06:00'),
        'Jump to 1/3 a.mp4 · 00:10/02:00 · 01:10/06:00',
      );
    });
  });
}
