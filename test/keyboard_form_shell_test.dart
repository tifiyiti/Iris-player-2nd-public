import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/widgets/adaptive/keyboard_form_shell.dart';

int _probeBuilds = 0;

class _ProbeForm extends StatelessWidget {
  const _ProbeForm();

  @override
  Widget build(BuildContext context) {
    _probeBuilds++;
    return KeyboardFormScaffold(
      title: const Text('probe'),
      onClose: () => Navigator.of(context).maybePop(),
      body: const SizedBox(height: 200, child: Text('body')),
      footer: TextButton(
        onPressed: () => Navigator.of(context).pop('done'),
        child: const Text('done'),
      ),
    );
  }
}

void main() {
  Widget app() => MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showAdaptiveKeyboardForm<String>(
                  context: context,
                  form: const _ProbeForm(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

  testWidgets('narrow width opens a bottom sheet', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(app());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('probe'), findsOneWidget);
  });

  testWidgets('enableDrag/isDismissible false pins the sheet open',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showAdaptiveKeyboardForm<String>(
                  context: context,
                  enableDrag: false,
                  isDismissible: false,
                  showDragHandle: false,
                  form: const _ProbeForm(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<BottomSheet>(find.byType(BottomSheet)).enableDrag,
      isFalse,
    );
    // Tapping the scrim must not dismiss when isDismissible is false.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('probe'), findsOneWidget);
  });

  testWidgets('wide layout opens a centered dialog', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(app());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('probe'), findsOneWidget);
  });

  testWidgets('route pop result propagates through the shell', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  result = await showAdaptiveKeyboardForm<String>(
                    context: context,
                    form: const _ProbeForm(),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('done'));
    await tester.pumpAndSettle();

    expect(result, 'done');
  });

  testWidgets('keyboard frames do not rebuild the cached form', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
    });

    await tester.pumpWidget(app());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Only keyboard height changes now — the cached form must not rebuild.
    _probeBuilds = 0;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(_probeBuilds, 0);
    expect(find.text('probe'), findsOneWidget);
  });

  testWidgets('text prompt returns the trimmed value', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    String? result;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showKeyboardTextPrompt(
                  context: context,
                  title: 'Rename',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    // Deferred l10n delegates load async — settle before tapping the opener.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  hi  ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(result, 'hi');
    expect(tester.takeException(), isNull);
  });

  testWidgets('text prompt validation keeps it open and shows the error',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showKeyboardTextPrompt(
                context: context,
                title: 'Rename',
                validate: (v) => v.isEmpty ? 'Required' : null,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    // Deferred l10n delegates load async — settle before tapping the opener.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Required'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('body actions run after the prompt closes, disabled ones are inert',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    int firstSelected = 0;
    int lastSelected = 0;
    String? result = 'untouched';
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showKeyboardTextPrompt(
                  context: context,
                  title: 'Jump',
                  bodyActions: [
                    KeyboardTextPromptAction(
                      label: 'First page',
                      icon: Icons.first_page,
                      onSelected: () => firstSelected++,
                    ),
                    KeyboardTextPromptAction(
                      label: 'Last page',
                      icon: Icons.last_page,
                      onSelected: () => lastSelected++,
                      enabled: false,
                    ),
                  ],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    // Deferred l10n delegates load async — settle before tapping the opener.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    TextButton action(String label) => tester.widget<TextButton>(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(TextButton),
          ),
        );

    expect(action('First page').onPressed, isNotNull);
    expect(action('Last page').onPressed, isNull);

    await tester.tap(find.text('First page'));
    await tester.pumpAndSettle();

    expect(firstSelected, 1);
    expect(lastSelected, 0);
    // Shortcuts own their side effect, so the prompt resolves like a cancel.
    expect(result, isNull);
    expect(find.text('Jump'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
