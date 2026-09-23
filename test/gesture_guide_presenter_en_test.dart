import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/phone/gesture_guide/controller/gesture_guide_presenter.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/store/gesture/gesture_actions.dart';
import 'package:iris/models/store/gesture_region.dart';

// NOTE: en companion of gesture_guide_presenter_test.dart — one locale per
// file, since flutter test cannot reliably load a second deferred l10n
// chunk after another locale ran in the same file.
Future<AppLocalizations> loadEn(WidgetTester tester) async {
  late AppLocalizations t;
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
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

void main() {
  testWidgets('en labels resolve from the en delegate', (tester) async {
    final t = await loadEn(tester);
    expect(describeAction(playPause, t).label, 'Play / Pause');
    expect(describeAction(openTags, t).label, 'Open Tag view');
    expect(
      describeAction(
        const GestureAction(
            type: GestureActionType.seekForward,
            duration: Duration(seconds: 10)),
        t,
      ).label,
      'Seek forward 10s',
    );
  });

  testWidgets('en intent titles resolve', (tester) async {
    final t = await loadEn(tester);
    expect(guideIntentTitle(GestureIntent.doubleTap, t), 'Double tap');
    expect(guideIntentTitle(GestureIntent.tap, t), 'Tap');
  });
}
