import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/db/db_module.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_storage_store.dart';
import 'package:iris/widgets/adaptive/keyboard_form_shell.dart';
import 'package:iris/widgets/dialogs/show_ftp_dialog.dart';

/// Dual-end layout + keyboard-frame guard for the FTP dialog (360px phone +
/// soft keyboard + large font), per the popup contract.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  setUpAll(() async {
    await DbModule.init(AppDatabase(NativeDatabase.memory()));
  });

  setUp(() async {
    useAppStore();
    await useAppStore().initialized;
    useStorageStore();
    await useStorageStore().initialized;
  });

  Widget tree({FTPStorage? storage}) {
    return StoreScope(
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () {
                  if (storage != null) {
                    useStorageStore().addStorage(storage);
                  }
                  showFTPDialog(context, storage: storage);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> pumpOpener(
    WidgetTester tester, {
    Size surface = const Size(360, 640),
    double keyboard = 0,
    FTPStorage? storage,
  }) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    await tester.pumpWidget(tree(storage: storage));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('renders on a 360x640 phone with keyboard insets and large font',
      (tester) async {
    await pumpOpener(tester, keyboard: 300);

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(FtpForm), findsOneWidget);
    expect(find.text('Add FTP storage'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('edit mode seeds the host and stays overflow-free', (tester) async {
    final storage = FTPStorage(
      id: 'f1',
      name: 'ftp',
      host: '10.0.0.2',
      basePath: const <String>['/'],
      port: '21',
      username: 'bob',
      password: 'secret',
    );

    await pumpOpener(tester, storage: storage);

    expect(find.text('Edit FTP storage'), findsOneWidget);
    expect(find.text('10.0.0.2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard frames do not rebuild the form', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
    });

    var builds = 0;
    FtpForm.debugOnFormBuild = () => builds++;
    addTearDown(() => FtpForm.debugOnFormBuild = null);

    await tester.pumpWidget(
      StoreScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showAdaptiveKeyboardForm<void>(
                    context: context,
                    form: FtpForm(
                      fillViewport: isKeyboardFormSheet(context),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // Deferred l10n delegates load async — settle before tapping the opener.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Only keyboard height changes now — the cached form must not rebuild.
    builds = 0;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(builds, 0);
    expect(find.text('Add FTP storage'), findsOneWidget);
  });
}
