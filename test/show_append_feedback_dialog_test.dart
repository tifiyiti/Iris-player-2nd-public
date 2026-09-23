import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/file.dart';
import 'package:iris/widgets/dialogs/show_append_feedback_dialog.dart';

/// Append feedback dialog (v14-D2): renders the before/after queue counts plus
/// the newly added file names (first 3 + ellipsis + total) so the user knows
/// the append landed.
void main() {
  FileItem file(String name) => FileItem(name: name, uri: '/$name');

  Future<void> pumpDialog(
    WidgetTester tester, {
    required List<FileItem> appended,
    required int beforeCount,
    required int afterCount,
  }) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showAppendFeedbackDialog(
                context,
                appended: appended,
                beforeCount: beforeCount,
                afterCount: afterCount,
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

  testWidgets('shows the before/after counts and the added item name',
      (tester) async {
    await pumpDialog(
      tester,
      appended: [file('movie.mp4')],
      beforeCount: 5,
      afterCount: 6,
    );
    expect(find.text('已添加到播放队列'), findsOneWidget);
    expect(find.text('添加前：5 项'), findsOneWidget);
    expect(find.text('添加后：6 项（新增 1 项）'), findsOneWidget);
    expect(find.text('• movie.mp4'), findsOneWidget);
  });

  testWidgets('shows the first three names then an ellipsis with the total',
      (tester) async {
    final appended = [for (var i = 1; i <= 5; i++) file('movie$i.mp4')];
    await pumpDialog(
      tester,
      appended: appended,
      beforeCount: 0,
      afterCount: 5,
    );
    expect(find.text('• movie1.mp4'), findsOneWidget);
    expect(find.text('• movie3.mp4'), findsOneWidget);
    expect(find.text('• movie4.mp4'), findsNothing);
    expect(find.text('…（共 5 项）'), findsOneWidget);
    expect(find.text('添加后：5 项（新增 5 项）'), findsOneWidget);
  });

  testWidgets('OK dismisses the dialog', (tester) async {
    await pumpDialog(
      tester,
      appended: [file('movie.mp4')],
      beforeCount: 0,
      afterCount: 1,
    );
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('确定'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(AlertDialog), findsNothing);
  });
}
