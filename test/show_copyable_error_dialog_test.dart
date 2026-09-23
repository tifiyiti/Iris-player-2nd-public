import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/widgets/dialogs/show_copyable_error_dialog.dart';
/// v15-D6: the uniform error dialog shows concrete, copyable error info.
void main() {
  Future<void> pumpDialog(
    WidgetTester tester, {
    required String message,
    String? title,
  }) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showCopyableErrorDialog(
                context,
                title: title,
                message: message,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    // Deferred l10n delegates load async — settle before tapping.
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('shows the error title and a selectable message', (tester) async {
    await pumpDialog(
      tester,
      title: '播放出错',
      message: '无法播放「x.mp4」：该文件不在当前播放队列中。',
    );

    expect(find.text('播放出错'), findsOneWidget);
    // The message is selectable/copyable (SelectableText).
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.text('无法播放「x.mp4」：该文件不在当前播放队列中。'),
        findsOneWidget);
  });

  testWidgets('copy button copies the message to the clipboard and closes',
      (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    const message = 'specific error detail for copy';
    await pumpDialog(tester, message: message);

    await tester.tap(find.text('复制'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(copied, message);
    // The copy action also dismisses the dialog.
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('OK closes the dialog', (tester) async {
    await pumpDialog(tester, message: 'oops');
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('确定'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(AlertDialog), findsNothing);
  });
}
