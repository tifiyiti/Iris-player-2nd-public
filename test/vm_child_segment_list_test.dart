import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/view/widgets/progress_chip.dart';
import 'package:iris/features/scenario_playback/model/domain/virtual_child_entry.dart';
import 'package:iris/features/virtual_media/model/domain/vm_item.dart';
import 'package:iris/features/virtual_media/store/vm_playback_store.dart';
import 'package:iris/features/virtual_media/view/vm_child_segment_list.dart';
import 'package:iris/l10n/app_localizations.dart';

VirtualChildEntry child(
  String key,
  String name, {
  int? durationMs,
  int occurrenceIndex = 0,
}) =>
    VirtualChildEntry(
      mediaKey: key,
      name: name,
      occurrenceIndex: occurrenceIndex,
      durationMs: durationMs,
      sizeInBytes: 1024,
    );

VirtualSegment seg(String key, String name, int occurrenceIndex) =>
    VirtualSegment(
      mediaKey: key,
      storageId: 'st1',
      path: [name],
      name: name,
      parentPath: '',
      durationMs: 1000,
      occurrenceIndex: occurrenceIndex,
    );

Future<List<int>> _pump(
  WidgetTester tester,
  List<VirtualChildEntry> children,
) async {
  final taps = <int>[];
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: VmChildSegmentList(
        children: children,
        onPlayChild: taps.add,
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return taps;
}

void main() {
  testWidgets('renders one row per child with names and durations',
      (tester) async {
    await _pump(tester, [
      child('st1:a/1.mp4', '1.mp4', durationMs: 65000),
      child('st1:a/2.mp4', '2.mp4', durationMs: 1000),
    ]);
    expect(find.text('1.mp4'), findsOneWidget);
    expect(find.text('2.mp4'), findsOneWidget);
    expect(find.text('01:05'), findsOneWidget);
    expect(find.text('00:01'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('tapping a child reports its index', (tester) async {
    final taps = await _pump(tester, [
      child('st1:a/1.mp4', '1.mp4', durationMs: 1000),
      child('st1:a/2.mp4', '2.mp4', durationMs: 1000),
    ]);
    await tester.tap(find.text('2.mp4'));
    await tester.pumpAndSettle();
    expect(taps, [1]);
  });

  testWidgets('lays out without overflow on a narrow phone', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pump(tester, [
      child('st1:a/1.mp4', 'a-very-long-child-file-name-that-should-ellipsize.mp4',
          durationMs: 3 * 3600 * 1000),
      child('st1:a/2.mp4', '2.mp4', durationMs: 1000),
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'shows each child\'s own progress, and 100% for a watched-through one',
      (tester) async {
    await _pump(tester, [
      // 50% of its own duration → 30/60 = 50%.
      VirtualChildEntry(
        mediaKey: 'st1:a/1.mp4',
        name: '1.mp4',
        durationMs: 60000,
        positionMs: 30000,
      ),
      // Watched through → 100% even though the position is stale.
      VirtualChildEntry(
        mediaKey: 'st1:a/2.mp4',
        name: '2.mp4',
        durationMs: 60000,
        positionMs: 1000,
        completed: true,
      ),
      // Never touched → no chip at all.
      VirtualChildEntry(
        mediaKey: 'st1:a/3.mp4',
        name: '3.mp4',
        durationMs: 60000,
      ),
    ]);
    expect(find.text('50 %'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.byType(ProgressChip), findsNWidgets(2));
  });

  testWidgets(
      'highlights only the playing occurrence of a duplicated child file',
      (tester) async {
    // Same mediaKey twice with different occurrences (`allowDuplicate`). The
    // active session sits on occurrence 1 — the highlight must land on the
    // second row, never alias both by media key.
    const key = 'st1:a/x.mp4';
    useVmPlaybackStore().replace(VmPlaybackState(
      item: VirtualMediaItem(
        ruleId: 'r',
        scopeKey: 'r|a|#1',
        rootPath: 'a',
        displayIndex: 1,
        displayName: 'g',
        segments: [seg(key, 'x.mp4', 0), seg(key, 'x.mp4', 1)],
      ),
      segmentIndex: 1,
    ));
    addTearDown(() => useVmPlaybackStore().replace(const VmPlaybackState()));

    await _pump(tester, [
      child(key, 'x.mp4', durationMs: 1000, occurrenceIndex: 0),
      child(key, 'x.mp4', durationMs: 1000, occurrenceIndex: 1),
    ]);

    final names = tester.widgetList<Text>(find.text('x.mp4')).toList();
    expect(names, hasLength(2));
    expect(names[0].style?.fontWeight, isNot(FontWeight.bold),
        reason: 'occurrence 0 must stay inactive while occurrence 1 plays');
    expect(names[1].style?.fontWeight, FontWeight.bold,
        reason: 'occurrence 1 is the playing segment and must highlight');
  });
}
