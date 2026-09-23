import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/scenario_playback/model/domain/virtual_child_entry.dart';
import 'package:iris/features/scenario_playback/view/widgets/vm_group_progress_chip.dart';
import 'package:iris/features/virtual_media/model/domain/vm_item.dart';
import 'package:iris/features/virtual_media/store/vm_playback_store.dart';
import 'package:iris/l10n/app_localizations.dart';

VirtualChildEntry child(
  String key,
  String name, {
  int? durationMs,
  int? positionMs,
  bool completed = false,
}) =>
    VirtualChildEntry(
      mediaKey: key,
      name: name,
      durationMs: durationMs,
      positionMs: positionMs,
      completed: completed,
    );

VirtualMediaItem group(List<VirtualSegment> segments) => VirtualMediaItem(
      ruleId: 'r',
      scopeKey: 'r|a|#1',
      rootPath: 'a',
      displayIndex: 1,
      displayName: 'g',
      segments: segments,
    );

VirtualSegment seg(String key, int durationMs) => VirtualSegment(
      mediaKey: key,
      storageId: 'st1',
      path: [key.split('/').last],
      name: key.split('/').last,
      parentPath: '',
      durationMs: durationMs,
    );

Future<void> pump(
  WidgetTester tester, {
  required List<VirtualChildEntry> children,
  required int totalDurationMs,
  required String anchorKey,
  required bool isCurrent,
}) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: VmGroupProgressChip(
        anchorKey: anchorKey,
        children: children,
        totalDurationMs: totalDurationMs,
        isCurrent: isCurrent,
        showWhenEmpty: isCurrent,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => useVmPlaybackStore().replace(const VmPlaybackState()));

  testWidgets('no session and nothing watched: stays invisible', (tester) async {
    await pump(
      tester,
      children: [
        child('st1:a/1.mp4', '1.mp4', durationMs: 60000),
        child('st1:a/2.mp4', '2.mp4', durationMs: 60000),
      ],
      totalDurationMs: 120000,
      anchorKey: 'st1:a/1.mp4',
      isCurrent: false,
    );
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('durable per-segment positions aggregate into the group %',
      (tester) async {
    // Half of the first segment watched → 30000/120000 = 25%.
    await pump(
      tester,
      children: [
        child('st1:a/1.mp4', '1.mp4', durationMs: 60000, positionMs: 30000),
        child('st1:a/2.mp4', '2.mp4', durationMs: 60000),
      ],
      totalDurationMs: 120000,
      anchorKey: 'st1:a/1.mp4',
      isCurrent: false,
    );
    expect(find.text('25 %'), findsOneWidget);
    // One chip only: nothing is "current" without a live session.
    expect(find.byType(Tooltip), findsOneWidget);
  });

  testWidgets('a watched-through child counts as its full duration',
      (tester) async {
    await pump(
      tester,
      children: [
        child('st1:a/1.mp4', '1.mp4',
            durationMs: 60000, positionMs: 10000, completed: true),
        child('st1:a/2.mp4', '2.mp4', durationMs: 60000, positionMs: 30000),
      ],
      totalDurationMs: 120000,
      anchorKey: 'st1:a/1.mp4',
      isCurrent: false,
    );
    // (60000 + 30000) / 120000 = 75%.
    expect(find.text('75 %'), findsOneWidget);
  });

  testWidgets('a live session shows the group AND the current segment',
      (tester) async {
    // Second segment is the fed one: group offset 60000 + 30000 = 75% of the
    // whole item, and 50% of its own 60s.
    useVmPlaybackStore().replace(VmPlaybackState(
      item: group([seg('st1:a/1.mp4', 60000), seg('st1:a/2.mp4', 60000)]),
      segmentIndex: 1,
      pendingSeekMs: 30000,
    ));

    await pump(
      tester,
      children: [
        child('st1:a/1.mp4', '1.mp4', durationMs: 60000),
        child('st1:a/2.mp4', '2.mp4', durationMs: 60000),
      ],
      totalDurationMs: 120000,
      anchorKey: 'st1:a/1.mp4',
      isCurrent: true,
    );
    expect(find.text('75 %'), findsOneWidget);
    expect(find.text('50 %'), findsOneWidget);
    expect(find.byType(Tooltip), findsNWidgets(2));
  });

  testWidgets('a live session on ANOTHER group leaves the row on durable data',
      (tester) async {
    // The highlight says "current" (e.g. a stale booking), but the session's
    // first segment is a different group: the row must not borrow its numbers.
    useVmPlaybackStore().replace(VmPlaybackState(
      item: group([seg('st1:b/1.mp4', 60000), seg('st1:b/2.mp4', 60000)]),
      segmentIndex: 1,
      pendingSeekMs: 30000,
    ));

    await pump(
      tester,
      children: [
        child('st1:a/1.mp4', '1.mp4', durationMs: 60000, positionMs: 30000),
        child('st1:a/2.mp4', '2.mp4', durationMs: 60000),
      ],
      totalDurationMs: 120000,
      anchorKey: 'st1:a/1.mp4',
      isCurrent: true,
    );
    expect(find.text('25 %'), findsOneWidget);
    expect(find.byType(Tooltip), findsOneWidget);
  });
}
