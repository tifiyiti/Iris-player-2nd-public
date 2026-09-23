import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/webdav_discovery/view/webdav_connect_error_dialog.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/enums/storage_list_error.dart';

/// Failure-first dialog: explains the unreachable endpoint, then lets the
/// user choose. Cancel must do nothing (browser stays closed, cache kept).
void main() {
  Widget tree(Future<WebdavConnectAction> Function(BuildContext) show) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final action = await show(context);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('chose:$action')),
                );
              }
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
  }

  testWidgets('failure dialog shows endpoint and cancel does nothing',
      (tester) async {
    await tester.pumpWidget(tree(
      (context) => showWebdavConnectFailure(
        context,
        endpoint: '192.168.1.9',
        errorKind: StorageListErrorKind.unreachable,
        errorDetail: 'no candidate host answered',
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('192.168.1.9'), findsWidgets);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(find.textContaining('chose:WebdavConnectAction.cancel'),
        findsOneWidget);
  });

  testWidgets('retry and edit choices are returned', (tester) async {
    await tester.pumpWidget(tree(
      (context) => showWebdavConnectFailure(
        context,
        endpoint: 'nas.local',
        errorKind: StorageListErrorKind.unauthorized,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(find.textContaining('chose:WebdavConnectAction.retry'),
        findsOneWidget);
  });
}
