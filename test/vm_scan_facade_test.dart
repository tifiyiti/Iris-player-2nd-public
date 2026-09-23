import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/virtual_media/model/domain/vm_item.dart';
import 'package:iris/features/virtual_media/scan/vm_scan_facade.dart';
import 'package:iris/l10n/app_localizations.dart';

Future<NavigatorState> pumpNavigator(WidgetTester tester) async {
  late NavigatorState navigator;
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(builder: (context) {
      navigator = Navigator.of(context);
      return const Scaffold(body: Text('home'));
    }),
  ));
  await tester.pumpAndSettle();
  return navigator;
}

VirtualSegment seg(String name, {int? durationMs}) {
  return VirtualSegment(
    mediaKey: 'st1:Shorts/$name',
    storageId: 'st1',
    path: ['Shorts', name],
    name: name,
    parentPath: 'Shorts',
    durationMs: durationMs,
  );
}

void main() {
  test('applyDbDurationsToSegments merges DB truth, ignores scan claims', () {
    final segs = [seg('1.mp4'), seg('2.mp4')];
    final out = applyDbDurationsToSegments(segs, {
      'st1:Shorts/1.mp4': 60000,
      'st1:Shorts/2.mp4': null,
    });
    expect(out[0].durationMs, 60000);
    expect(out[1].durationMs, isNull);
  });

  test('healedKeysFromDb only heals positive DB durations', () {
    final segs = [seg('1.mp4'), seg('2.mp4'), seg('3.mp4')];
    // Scan claims all three, but DB only confirms one.
    final healed = healedKeysFromDb(
      segs,
      {'st1:Shorts/1.mp4', 'st1:Shorts/2.mp4', 'st1:Shorts/3.mp4'},
      {
        'st1:Shorts/1.mp4': 60000,
        'st1:Shorts/2.mp4': null,
        'st1:Shorts/3.mp4': 0,
      },
    );
    expect(healed, {'st1:Shorts/1.mp4'});
  });

  test('shouldOfferSlowScan true only when leftover remains', () {
    expect(shouldOfferSlowScan(['k1']), isTrue);
    expect(shouldOfferSlowScan([]), isFalse);
  });

  test('filterScanHealedByDb re-reads DB, never trusts scan keys', () async {
    final segs = [seg('1.mp4'), seg('2.mp4')];
    final healed = await filterScanHealedByDb(
      segs,
      {'st1:Shorts/1.mp4', 'st1:Shorts/2.mp4'},
      readDb: (_) async => {'st1:Shorts/1.mp4': 60000},
    );
    expect(healed, {'st1:Shorts/1.mp4'});
  });

  testWidgets('slow-scan confirm offers abort, normal and slow paths',
      (tester) async {
    final navigator = await pumpNavigator(tester);
    final future = showVmSlowScanConfirmDialog(
      navigator,
      groupName: '合集',
      leftoverNames: const ['1.mp4'],
    );
    await tester.pumpAndSettle();
    expect(find.text('仍有缺失时长'), findsOneWidget);
    expect(find.text('取消播放'), findsOneWidget);
    expect(find.text('仅普通播放'), findsOneWidget);
    expect(find.text('继续慢扫'), findsOneWidget);
    await tester.tap(find.text('继续慢扫'));
    expect(await future, VmSlowScanChoice.slowScan);
  });

  testWidgets('slow-scan confirm abort path', (tester) async {
    final navigator = await pumpNavigator(tester);
    final future = showVmSlowScanConfirmDialog(
      navigator,
      groupName: '合集',
      leftoverNames: const ['1.mp4'],
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消播放'));
    expect(await future, VmSlowScanChoice.abort);
  });
}
