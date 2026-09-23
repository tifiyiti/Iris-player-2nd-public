import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/phone/gesture_guide/controller/gesture_guide_presenter.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/store/gesture/gesture_actions.dart';
import 'package:iris/models/store/gesture/gesture_layouts_default.dart';
import 'package:iris/models/store/gesture_region.dart';

Future<AppLocalizations> loadZh(WidgetTester tester) async {
  late AppLocalizations t;
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(builder: (ctx) {
      t = AppLocalizations.of(ctx)!;
      return const SizedBox();
    }),
  ));
  await tester.pumpAndSettle();
  return t;
}

// NOTE: en cases live apart (see gesture_guide_presenter_en_test.dart) —
// one locale per file, since flutter test cannot reliably load a second
// deferred l10n chunk after another locale ran in the same file.
void main() {
  group('buildGuideSections', () {
    testWidgets('orders intents (doubleTap first) and drops empty/hover layers',
        (tester) async {
      final t = await loadZh(tester);
      final sections = buildGuideSections(defaultGestureLayouts, t);

      expect(sections.first.intent, GestureIntent.doubleTap);
      // hover is a desktop-only concept that must never appear in the phone guide.
      final intents = sections.map((s) => s.intent).toList();
      expect(intents, isNot(contains(GestureIntent.hover)));
      expect(intents, contains(GestureIntent.longPressPanVertical));
      // doubleTap + tap + panHorizontal + panVertical + longPress +
      // longPressPanHorizontal + longPressPanVertical survive.
      expect(sections.length, 7);
    });

    testWidgets('carries regions with their actions', (tester) async {
      final t = await loadZh(tester);
      final sections = buildGuideSections(defaultGestureLayouts, t);
      final dt = sections.firstWhere((s) => s.intent == GestureIntent.doubleTap);

      // 3×3 spec: nine strict grid cells, tag only at bottom-center.
      expect(dt.regions.length, 9);
      expect(dt.regions.map((r) => r.action.type).toSet(),
          {GestureActionType.seekBackward, GestureActionType.playPause, GestureActionType.seekForward, GestureActionType.openTagPlaySheet});
      expect(dt.regions.where((r) => r.action.type == GestureActionType.openTagPlaySheet).length, 1);
    });

    testWidgets('tagPlay layout exposes the openTags bottom-center region',
        (tester) async {
      final t = await loadZh(tester);
      final sections = buildGuideSections(tagPlayGestureLayouts, t);
      final dt = sections.firstWhere((s) => s.intent == GestureIntent.doubleTap);

      expect(dt.regions.length, 9);
      final tagCell = dt.regions.firstWhere(
        (r) => r.normalizedRect.contains(const Offset(0.5, 0.9)),
      );
      expect(tagCell.action.type, GestureActionType.openTagPlaySheet);
    });
  });

  group('describeAction', () {
    testWidgets('playPause / openTagPlaySheet / none map to stable labels',
        (tester) async {
      final t = await loadZh(tester);
      expect(describeAction(playPause, t).label, '播放 / 暂停');
      expect(describeAction(openTags, t).label, '打开 Tag 视图');
      final d = describeAction(none, t);
      expect(d.label, '未设置');
      expect(d.active, isFalse);
    });

    testWidgets('seek formatting follows the optional duration value',
        (tester) async {
      final t = await loadZh(tester);
      expect(describeAction(seekF, t).label, '快进');
      expect(
        describeAction(
          const GestureAction(
              type: GestureActionType.seekForward, duration: Duration(seconds: 10)),
          t,
        ).label,
        '快进 10 秒',
      );
      expect(describeAction(seekB, t).label, '快退');
    });

    testWidgets('every configured action renders with an icon and active flag',
        (tester) async {
      final t = await loadZh(tester);
      for (final type in GestureActionType.values) {
        final d = describeAction(GestureAction(type: type), t);
        expect(d.icon, isNotNull, reason: 'missing icon for $type');
        expect(d.label, isNotEmpty);
        if (type != GestureActionType.none) {
          expect(d.active, isTrue, reason: '$type must be active');
        }
      }
    });
  });
}
