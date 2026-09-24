import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/playback_tools/services/screenshot_service.dart';
import 'package:iris/features/playback_tools/view/screenshot_feedback.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/l10n/app_localizations_en.dart';
import 'package:iris/l10n/app_localizations_zh.dart';

void main() {
  group('screenshotFailureMessage', () {
    final en = AppLocalizationsEn();
    final zh = AppLocalizationsZh();

    test('maps every failure kind to its localized English text', () {
      expect(
        screenshotFailureMessage(
            en, const ScreenshotFailure(ScreenshotFailureKind.frameGrab,
                detail: 'boom')),
        'Could not grab the frame: boom',
      );
      expect(
        screenshotFailureMessage(
            en, const ScreenshotFailure(ScreenshotFailureKind.emptyFrame)),
        'The backend returned no frame data.',
      );
      expect(
        screenshotFailureMessage(
            en, const ScreenshotFailure(ScreenshotFailureKind.undecodable)),
        'The frame data could not be decoded as an image.',
      );
      expect(
        screenshotFailureMessage(
            en, const ScreenshotFailure(ScreenshotFailureKind.write,
                detail: 'disk full')),
        'Could not write the file: disk full',
      );
      expect(
        screenshotFailureMessage(
            en,
            const ScreenshotFailure(ScreenshotFailureKind.noDir,
                detail: 'no provider')),
        'Could not locate the save folder: no provider',
      );
      expect(
        screenshotFailureMessage(
            en, const ScreenshotFailure(ScreenshotFailureKind.timeout)),
        'Screenshot timed out (15s), please retry',
      );
      expect(
        screenshotFailureMessage(
            en, const ScreenshotFailure(ScreenshotFailureKind.unknown)),
        'Screenshot failed (unexpected error)',
      );
    });

    test('localizes to Chinese (no hardcoded string survives)', () {
      expect(
        screenshotFailureMessage(
            zh, const ScreenshotFailure(ScreenshotFailureKind.write,
                detail: 'x')),
        '写入文件失败：x',
      );
      expect(
        screenshotFailureMessage(
            zh, const ScreenshotFailure(ScreenshotFailureKind.emptyFrame)),
        '后端未返回画面数据。',
      );
    });
  });

  group('showScreenshotFeedback', () {
    late NavigatorState nav;

    Future<void> pumpHost(WidgetTester tester, Locale locale) async {
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // Resolve the navigator from inside `home`: it only builds once the
        // (deferred) localizations have loaded, so this is non-null after the
        // settle — unlike a navigatorKey, which is null while l10n loads.
        home: Builder(builder: (context) {
          nav = Navigator.of(context);
          return const Scaffold(body: SizedBox.shrink());
        }),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('a plain success shows only the path', (tester) async {
      await pumpHost(tester, const Locale('en'));
      // showMessageDialog awaits the dialog's dismissal — never await it here.
      unawaited(showScreenshotFeedback(
          nav, const ScreenshotSuccess('D:/a.png')));
      await tester.pumpAndSettle();
      expect(find.text('D:/a.png'), findsOneWidget);
    });

    testWidgets('a skipped custom dir composes ONE ARB message (path + note)',
        (tester) async {
      await pumpHost(tester, const Locale('en'));
      unawaited(showScreenshotFeedback(
        nav,
        const ScreenshotSuccess('D:/a.png', customDirSkipped: true),
      ));
      await tester.pumpAndSettle();
      // The note is a placeholder inside the ARB string — the old code built
      // this by concatenating two display strings.
      expect(
        find.text('D:/a.png\n\nThe selected folder is not writable, so the '
            'screenshot was saved to the default folder.'),
        findsOneWidget,
      );
    });

    testWidgets('a failure renders the localized reason', (tester) async {
      await pumpHost(tester, const Locale('en'));
      unawaited(showScreenshotFeedback(
        nav,
        const ScreenshotFailure(ScreenshotFailureKind.noDir,
            detail: 'no provider'),
      ));
      await tester.pumpAndSettle();
      // Proves the dialog routes the failure through the ARB mapping (the
      // exact zh wording is covered by the screenshotFailureMessage unit
      // tests, which do not depend on deferred-l10n load timing).
      expect(
        find.text('Could not locate the save folder: no provider'),
        findsOneWidget,
      );
    });
  });
}
