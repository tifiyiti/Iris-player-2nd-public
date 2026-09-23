import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/scenario_playback/actions/scenario_playback_actions.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/widgets/dialogs/show_no_media_confirm_dialog.dart';

/// D14/D15: the shared No Media confirm dialog and the
/// `runPlayActionWithNoMediaConfirm` helper that routes
/// [PlaybackUnavailableException] to the dialog (confirm → force retry,
/// cancel → no-op) and every other failure to the uniform error dialog.
void main() {
  Future<void> pumpTrigger(
    WidgetTester tester, {
    required Future<void> Function(BuildContext context) onPressed,
  }) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => onPressed(context),
              child: const Text('run'),
            ),
          ),
        ),
      ),
    ));
    // Deferred l10n delegates load async — settle before tapping.
    await tester.pumpAndSettle();
    await tester.tap(find.text('run'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('dialog confirm returns true and cancel returns false',
      (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                result = await showNoMediaConfirmDialog(context);
              },
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
    expect(find.text('未找到可播内容'), findsOneWidget);
    await tester.tap(find.text('仍要加入'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(result, isTrue);

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('取消'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(result, isFalse);
  });

  testWidgets(
      'PlaybackUnavailableException shows No Media; confirm retries with force',
      (tester) async {
    var attempts = 0;
    NoMediaActionResult? result;
    await pumpTrigger(tester, onPressed: (ctx) async {
      result = await ScenarioPlaybackActions.runPlayActionWithNoMediaConfirm(
        ctx,
        showWorkspaceNotice: false,
        action: ({bool force = false}) async {
          attempts++;
          if (!force) {
            throw const PlaybackUnavailableException('所选项目均不在媒体数据库中。');
          }
        },
      );
    });
    expect(find.text('未找到可播内容'), findsOneWidget);
    expect(attempts, 1);
    await tester.tap(find.text('仍要加入'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(attempts, 2);
    expect(result, NoMediaActionResult.forced);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('cancel keeps state and does not retry with force', (tester) async {
    var attempts = 0;
    NoMediaActionResult? result;
    await pumpTrigger(tester, onPressed: (ctx) async {
      result = await ScenarioPlaybackActions.runPlayActionWithNoMediaConfirm(
        ctx,
        showWorkspaceNotice: false,
        action: ({bool force = false}) async {
          attempts++;
          if (!force) {
            throw const PlaybackUnavailableException('无内容');
          }
        },
      );
    });
    expect(find.text('未找到可播内容'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(attempts, 1);
    expect(result, NoMediaActionResult.cancelled);
  });

  testWidgets('playable first attempt returns success', (tester) async {
    NoMediaActionResult? result;
    await pumpTrigger(tester, onPressed: (ctx) async {
      result = await ScenarioPlaybackActions.runPlayActionWithNoMediaConfirm(
        ctx,
        showWorkspaceNotice: false,
        action: ({bool force = false}) async {},
      );
    });
    expect(find.byType(AlertDialog), findsNothing);
    expect(result, NoMediaActionResult.success);
  });

  testWidgets('other exceptions surface the uniform error dialog', (tester) async {
    await pumpTrigger(tester, onPressed: (ctx) async {
      await ScenarioPlaybackActions.runPlayActionWithNoMediaConfirm(
        ctx,
        showWorkspaceNotice: false,
        action: ({bool force = false}) async {
          throw StateError('boom');
        },
      );
    });
    expect(find.text('播放出错'), findsOneWidget);
    expect(find.textContaining('播放失败'), findsOneWidget);
  });

  testWidgets('append confirm label uses 强制空追加', (tester) async {
    await pumpTrigger(tester, onPressed: (ctx) async {
      await ScenarioPlaybackActions.runPlayActionWithNoMediaConfirm(
        ctx,
        showWorkspaceNotice: false,
        action: ({bool force = false}) async {
          if (!force) {
            throw const PlaybackUnavailableException('无内容');
          }
        },
        append: true,
      );
    });
    expect(find.text('强制空追加'), findsOneWidget);
  });
}
