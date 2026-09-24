import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/playback_tools/view/screenshot_save_path_dialog.dart'
    show ScreenshotDirForm, showScreenshotSavePathDialog;
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/store/use_app_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  setUp(() async {
    useAppStore();
    await useAppStore().initialized;
  });

  tearDown(() async {
    await useAppStore().updateScreenshotMobileDir('');
    await useAppStore().updateScreenshotDesktopDir('');
  });

  Widget tree(Size surface, double keyboard, {required bool isMobile}) {
    return StoreScope(
      child: MaterialApp(
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
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showScreenshotSavePathDialog(context,
                      isMobile: isMobile),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> pumpOpener(
    WidgetTester tester, {
    required bool isMobile,
    Size surface = const Size(360, 640),
    double keyboard = 0,
  }) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(tree(surface, keyboard, isMobile: isMobile));
    // Route entrance + possible autofocus cursor blink: bounded pumps instead
    // of pumpAndSettle (the blinking caret keeps scheduling frames).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('open'));
    // Route entrance + possible autofocus cursor blink: bounded pumps instead
    // of pumpAndSettle (the blinking caret keeps scheduling frames).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('screenshot dir dialog 360px + keyboard + large font: no overflow',
      (tester) async {
    await pumpOpener(tester, isMobile: true, keyboard: 300);
    expect(tester.takeException(), isNull);
    expect(find.text('截屏保存目录'), findsOneWidget);
    expect(find.text('选择目录'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('screenshotDirInput')), findsOneWidget);
  });

  testWidgets('keyboard frames do not rebuild the form', (tester) async {
    const surface = Size(360, 640);
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    Future<void> pumpKeyboard(double keyboard) {
      return tester.pumpWidget(tree(surface, keyboard, isMobile: true));
    }

    var builds = 0;
    ScreenshotDirForm.debugOnFormBuild = () => builds++;
    addTearDown(() => ScreenshotDirForm.debugOnFormBuild = null);

    await pumpKeyboard(0);
    // Route entrance + possible autofocus cursor blink: bounded pumps instead
    // of pumpAndSettle (the blinking caret keeps scheduling frames).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('open'));
    // Route entrance + possible autofocus cursor blink: bounded pumps instead
    // of pumpAndSettle (the blinking caret keeps scheduling frames).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);

    // Only keyboard height changes now — the cached form must not rebuild.
    builds = 0;
    await pumpKeyboard(300);
    // Route entrance + possible autofocus cursor blink: bounded pumps instead
    // of pumpAndSettle (the blinking caret keeps scheduling frames).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    expect(builds, 0);
    expect(find.text('选择目录'), findsOneWidget);
  });

  testWidgets('desktop shell renders the same form', (tester) async {
    await pumpOpener(
      tester,
      isMobile: false,
      surface: const Size(1280, 800),
    );
    expect(tester.takeException(), isNull);
    // Desktop autofocus grabs the input at open, so the header is folded
    // by design — the form body (pick + paste + footer) is the assertion.
    expect(find.text('选择目录'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('screenshotDirInput')), findsOneWidget);
    expect(find.text('恢复默认'), findsOneWidget);
  });

  testWidgets('applying a valid pasted path writes to the store',
      (tester) async {
    await pumpOpener(tester, isMobile: false);
    expect(tester.takeException(), isNull);
    await tester.enterText(
      find.byKey(const ValueKey('screenshotDirInput')),
      r'D:/Photos/IRIS',
    );
    await tester.tap(find.text('应用'));
    // Route entrance + possible autofocus cursor blink: bounded pumps instead
    // of pumpAndSettle (the blinking caret keeps scheduling frames).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    expect(useAppStore().state.screenshotDesktopDir, isNotEmpty);
  });

  testWidgets('an unwritable pick shows a notice and keeps the store',
      (tester) async {
    await useAppStore().updateScreenshotMobileDir('E:/keep');
    ScreenshotDirForm.debugPickResolved =
        () async => (path: '', skipped: true);
    addTearDown(() => ScreenshotDirForm.debugPickResolved = null);

    await pumpOpener(tester, isMobile: true);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('screenshotDirPickUp')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The rejection is explained to the user...
    expect(find.text('该文件夹不可写入，已保留当前保存目录。'), findsOneWidget);
    // ...and the previously effective directory is NOT silently reset to ''.
    expect(useAppStore().state.screenshotMobileDir, 'E:/keep');
  });
}
