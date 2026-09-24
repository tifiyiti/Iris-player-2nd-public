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
import 'package:iris/widgets/dialogs/show_webdav_dialog.dart';

/// Dual-end layout + keyboard-frame guard for the WebDAV dialog (360px phone +
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

  Widget tree({WebDAVStorage? storage}) {
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
                  // Seed through the SCOPED store so the dialog sees it.
                  if (storage != null) {
                    useStorageStore().addStorage(storage);
                  }
                  showWebDAVDialog(context, storage: storage);
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
    WebDAVStorage? storage,
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
    // Route entrance + possible autofocus cursor blink: bounded pumps instead
    // of pumpAndSettle (the blinking caret keeps scheduling frames).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('renders on a 360x640 phone with keyboard insets and large font',
      (tester) async {
    await pumpOpener(tester, keyboard: 300);

    // Migrated off AlertDialog (whose IntrinsicWidth relayouts the whole form
    // per keyboard frame) onto the cached keyboard shell.
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(WebDavForm), findsOneWidget);
    expect(find.text('Add WebDAV storage'), findsOneWidget);
    // The hint expansion is the tallest content state — it must also fit.
    await tester.tap(find.text('Host format & scan notes'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    expect(tester.takeException(), isNull);
  });

  testWidgets('edit mode seeds the host and stays overflow-free', (tester) async {
    final storage = WebDAVStorage(
      id: 's1',
      name: 'nas',
      host: '192.168.1.*',
      resolvedHosts: const <String>['192.168.1.7'],
      basePath: const <String>['/'],
      port: '5005',
      username: 'alice',
      password: 'secret',
      https: false,
    );

    await pumpOpener(tester, storage: storage);

    expect(find.text('Edit WebDAV storage'), findsOneWidget);
    expect(find.text('192.168.1.*'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a locked entry seeds every field but the password, and Save stays gated',
      (tester) async {
    // A decrypt-failed placeholder: same entry shape, empty password.
    final locked = WebDAVStorage(
      id: 's1',
      name: 'nas',
      host: '192.168.*.*',
      resolvedHosts: const <String>['192.168.1.7'],
      basePath: const <String>['/media'],
      port: '5005',
      username: 'alice',
      password: '',
      https: false,
      dataScopeId: 'scope-1',
    );

    await pumpOpener(tester, storage: locked);

    expect(find.text('Edit WebDAV storage'), findsOneWidget);
    // Everything except the password is pre-filled, so the user only retypes
    // that — the wildcard/DHCP resolved-host cache survives the re-auth.
    expect(find.text('192.168.*.*'), findsOneWidget);
    expect(find.text('5005'), findsOneWidget);
    expect(find.text('alice'), findsOneWidget);
    expect(find.text('/media'), findsOneWidget);
    // Save is gated on a successful connection test, so an empty password can
    // never be written over the (currently unreadable) stored one.
    final save =
        tester.widget<TextButton>(find.widgetWithText(TextButton, 'Save'));
    expect(save.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders on desktop width through the dialog shell', (tester) async {
    await pumpOpener(tester, surface: const Size(1280, 800));

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Add WebDAV storage'), findsOneWidget);
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
    WebDavForm.debugOnFormBuild = () => builds++;
    addTearDown(() => WebDavForm.debugOnFormBuild = null);

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
                    form: WebDavForm(
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
    expect(find.text('Add WebDAV storage'), findsOneWidget);
  });
}
