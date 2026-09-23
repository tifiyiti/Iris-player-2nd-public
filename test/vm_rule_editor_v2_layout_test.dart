import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/virtual_media/model/domain/vm_rule.dart';
import 'package:iris/features/virtual_media/model/enum/vm_enums.dart';
import 'package:iris/features/virtual_media/view/vm_rule_editor_v2.dart';
import 'package:iris/l10n/app_localizations.dart';

VirtualMediaRule _patternRule() => VirtualMediaRule(
      id: 'vm_test',
      name: '测试规则',
      matchMode: VmMatchMode.patternDir,
      patterns: const [
        VmPatternEntry(kind: VmPatternKind.suffix, text: '第1季'),
        VmPatternEntry(kind: VmPatternKind.contains, text: '正片'),
      ],
    );

Future<void> _pumpV2(
  WidgetTester tester, {
  required Widget child,
  Size surface = const Size(360, 700),
  double keyboard = 0,
}) async {
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        // NOTE: size must be explicit — a bare MediaQueryData defaults to
        // Size.zero and would silently invalidate the dialog constraints.
        data: MediaQueryData(
          size: surface,
          viewInsets: EdgeInsets.only(bottom: keyboard),
          // Phone-realistic: larger system font exposes fixed-width rows.
          textScaler: const TextScaler.linear(1.3),
        ),
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          body: child,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('V2 narrow 360px: dialog shell does not overflow',
      (tester) async {
    await _pumpV2(tester, child: VmRuleEditorV2Dialog(initial: _patternRule()));
    expect(tester.takeException(), isNull);
    expect(find.text('保存'), findsOneWidget);
  });

  testWidgets('V2 narrow 360px: sheet shell does not overflow',
      (tester) async {
    await _pumpV2(tester, child: VmRuleEditorV2Sheet(initial: _patternRule()));
    expect(tester.takeException(), isNull);
    expect(find.text('保存'), findsOneWidget);
  });

  testWidgets('V2 keyboard shown: sheet save stays above the keyboard',
      (tester) async {
    const surface = Size(360, 700);
    const keyboard = 300.0;
    await _pumpV2(
      tester,
      surface: surface,
      keyboard: keyboard,
      child: VmRuleEditorV2Sheet(initial: _patternRule()),
    );
    expect(tester.takeException(), isNull);
    final saveRect = tester.getRect(find.text('保存'));
    expect(saveRect.bottom, lessThanOrEqualTo(surface.height - keyboard));
  });

  testWidgets('V2 wide 1000px: dialog shell does not overflow',
      (tester) async {
    await _pumpV2(
      tester,
      surface: const Size(1000, 800),
      child: VmRuleEditorV2Dialog(initial: _patternRule()),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('保存'), findsOneWidget);
  });

  testWidgets('V2 keyboard frames do not rebuild the form', (tester) async {
    const surface = Size(360, 700);
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    Future<void> pumpKeyboard(double keyboard) {
      return tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(
              size: surface,
              viewInsets: EdgeInsets.only(bottom: keyboard),
              textScaler: const TextScaler.linear(1.3),
            ),
            child: Scaffold(
              resizeToAvoidBottomInset: false,
              body: VmRuleEditorV2Sheet(initial: _patternRule()),
            ),
          ),
        ),
      );
    }

    var builds = 0;
    VmRuleEditorFormV2.debugOnFormBuild = () => builds++;
    addTearDown(() => VmRuleEditorFormV2.debugOnFormBuild = null);

    await pumpKeyboard(0);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Only keyboard height changes now — the cached form must not rebuild.
    builds = 0;
    await pumpKeyboard(300);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(builds, 0);
    expect(find.text('保存'), findsOneWidget);
  });
}
