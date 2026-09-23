import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/widgets/dialogs/storage_scope_link.dart';

WebDAVStorage _webdav({
  required String id,
  String host = '192.168.1.5',
  List<String> basePath = const <String>['/'],
  String? dataScopeId,
}) =>
    WebDAVStorage(
      id: id,
      name: id,
      host: host,
      basePath: basePath,
      port: '5005',
      username: 'alice',
      password: 'p',
      https: false,
      dataScopeId: dataScopeId,
    );

Future<void> _pumpHarness(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      locale: Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('confirm links the candidate to the matched scope',
      (tester) async {
    await _pumpHarness(tester);
    final future = resolveSharedLibraryLink(
      tester.element(find.byType(Scaffold)),
      _webdav(id: 'b'),
      [_webdav(id: 'a')],
    );
    await tester.pumpAndSettle();

    expect(find.text('Use the same media library?'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final result = await future;
    expect(result, isNotNull);
    expect(result!.dataScopeId, 'a');
  });

  testWidgets('cancel aborts the save (null)', (tester) async {
    await _pumpHarness(tester);
    final future = resolveSharedLibraryLink(
      tester.element(find.byType(Scaffold)),
      _webdav(id: 'b'),
      [_webdav(id: 'a')],
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(await future, isNull);
  });

  testWidgets('no match returns an independent (scope-cleared) entry',
      (tester) async {
    await _pumpHarness(tester);
    final result = await resolveSharedLibraryLink(
      tester.element(find.byType(Scaffold)),
      _webdav(id: 'b', basePath: const ['music']),
      [_webdav(id: 'a', basePath: const ['movies'])],
    );
    await tester.pumpAndSettle();

    expect(find.text('Use the same media library?'), findsNothing);
    expect(result, isNotNull);
    expect(result!.dataScopeId, isNull);
  });

  testWidgets('edit staying in its own scope never prompts', (tester) async {
    await _pumpHarness(tester);
    final result = await resolveSharedLibraryLink(
      tester.element(find.byType(Scaffold)),
      _webdav(id: 'b', dataScopeId: 'a'),
      [_webdav(id: 'a'), _webdav(id: 'b', dataScopeId: 'a')],
      isEdit: true,
      originalScopeId: 'a',
    );
    await tester.pumpAndSettle();

    expect(find.text('Use the same media library?'), findsNothing);
    expect(result!.dataScopeId, 'a');
  });

  testWidgets('owner self-edit resolves its own linked sibling silently',
      (tester) async {
    await _pumpHarness(tester);
    // Owner 'a' (scope null) with linked sibling 'b' (scope 'a'); editing the
    // owner must not prompt and must stay independent (NULL).
    final result = await resolveSharedLibraryLink(
      tester.element(find.byType(Scaffold)),
      _webdav(id: 'a'),
      [_webdav(id: 'a'), _webdav(id: 'b', dataScopeId: 'a')],
      isEdit: true,
      originalScopeId: null,
    );
    await tester.pumpAndSettle();

    expect(find.text('Use the same media library?'), findsNothing);
    expect(result!.dataScopeId, isNull);
  });

  testWidgets('edit joining a different scope prompts; cancel keeps original',
      (tester) async {
    await _pumpHarness(tester);
    final future = resolveSharedLibraryLink(
      tester.element(find.byType(Scaffold)),
      _webdav(id: 'b', dataScopeId: 'a'),
      [_webdav(id: 'c')],
      isEdit: true,
      originalScopeId: 'a',
    );
    await tester.pumpAndSettle();

    expect(find.text('Use the same media library?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    final result = await future;
    expect(result, isNotNull);
    expect(result!.dataScopeId, 'a'); // original link preserved, edit not lost
  });
}
