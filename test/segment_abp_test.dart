import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/model/domain/background_mapping.dart';
import 'package:iris/features/background_playback/model/enum/mapping_action.dart';
import 'package:iris/features/background_playback/view/background_mapping_editor.dart';
import 'package:iris/features/background_playback/view/segment_abp_slider.dart';
import 'package:iris/models/file.dart';

Widget _host(Widget child, {double width = 360, double height = 30}) =>
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: height,
            child: SliderTheme(
              data: const SliderThemeData(
                trackHeight: 4,
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );

MappingSegment _seg(int id, int bgStart, int bgEnd) => MappingSegment(
      id: id,
      action: MappingAction.playMedia,
      fgStartMs: bgStart,
      fgEndMs: bgEnd,
      bgStorageId: 'local',
      bgPath: 'b.mp4',
      bgStartMs: bgStart,
      bgEndMs: bgEnd,
    );

void main() {
  group('SegmentAbpTrack', () {
    testWidgets('renders A / centre / B handles on the bg axis', (tester) async {
      await tester.pumpWidget(_host(SegmentAbpTrack(
        bgDurMs: 100000,
        startMs: 20000,
        endMs: 50000,
        sameFileExisting: const [],
        editingId: 0,
        onChangeStart: (_) {},
        onChangeEnd: (_) {},
        onTranslate: (_) {},
      )));
      expect(find.byKey(const ValueKey('segment_handle_start')), findsOneWidget);
      expect(find.byKey(const ValueKey('segment_handle_center')), findsOneWidget);
      expect(find.byKey(const ValueKey('segment_handle_end')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dragging A/B reports bg-axis milliseconds', (tester) async {
      int? newStart;
      int? newEnd;
      int? translated;
      await tester.pumpWidget(_host(SegmentAbpTrack(
        bgDurMs: 100000,
        startMs: 20000,
        endMs: 50000,
        sameFileExisting: [_seg(9, 60000, 80000)],
        editingId: 0,
        onChangeStart: (v) => newStart = v,
        onChangeEnd: (v) => newEnd = v,
        onTranslate: (v) => translated = v,
      )));

      await tester.drag(find.byKey(const ValueKey('segment_handle_start')),
          const Offset(24, 0));
      await tester.pump();
      expect(newStart, isNotNull);
      expect(newStart!, greaterThan(20000));

      await tester.drag(find.byKey(const ValueKey('segment_handle_end')),
          const Offset(24, 0));
      await tester.pump();
      expect(newEnd, isNotNull);
      expect(newEnd!, greaterThan(50000));

      await tester.drag(find.byKey(const ValueKey('segment_handle_center')),
          const Offset(24, 0));
      await tester.pump();
      expect(translated, isNotNull);
      expect(translated!, greaterThan(0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('fits a 320px width without overflow', (tester) async {
      await tester.pumpWidget(_host(
        SegmentAbpTrack(
          bgDurMs: 7200000,
          startMs: 0,
          endMs: 7200000,
          sameFileExisting: [_seg(1, 0, 60000), _seg(2, 3600000, 3660000)],
          editingId: 0,
          onChangeStart: (_) {},
          onChangeEnd: (_) {},
          onTranslate: (_) {},
        ),
        width: 320,
      ));
      expect(tester.takeException(), isNull);
    });
  });

  group('seedSegmentDraft', () {
    test('defaults A/B to the WHOLE bg-feasible range of the alignment', () {
      // off = bgPos − fgPos = 30s → A = max(0, −off) = 0,
      // B = min(fgDur, bgDur − off) = 570s.
      final d = seedSegmentDraft(
        fgPosMs: 10000,
        fgDurMs: 600000,
        bgPosMs: 40000,
        bgDurMs: 600000,
        bgStorageId: 'local',
        bgPath: '/m/b.mp4',
      )!;
      expect(d.span.fgStartMs, 0);
      expect(d.span.fgEndMs, 570000);
      // bg window follows the bg file's own position (1:1 offset).
      expect(d.span.bgOffsetMs, 30000);
      expect(d.bgStorageId, 'local');
    });

    test('A lands on the bg 00:00 align point, not the playhead', () {
      // bg lags the playhead by 590s → bg 00:00 only appears at fg 590s.
      final d = seedSegmentDraft(
        fgPosMs: 590000,
        fgDurMs: 600000,
        bgPosMs: 0,
        bgDurMs: 600000,
      )!;
      expect(d.span.fgStartMs, 590000);
      expect(d.span.fgEndMs, 600000);
      expect(d.span.lengthMs, 10000);
    });

    test('B never passes the bg tail when bg is shorter', () {
      final d = seedSegmentDraft(
        fgPosMs: 0,
        fgDurMs: 600000,
        bgPosMs: 0,
        bgDurMs: 30000,
      )!;
      expect(d.span.fgStartMs, 0);
      expect(d.span.fgEndMs, 30000);
      expect(d.span.bgEndMs, lessThanOrEqualTo(30000));
    });

    test('returns null without a foreground duration', () {
      expect(
        seedSegmentDraft(fgPosMs: 0, fgDurMs: 0, bgPosMs: 0, bgDurMs: 1000),
        isNull,
      );
    });
  });

  group('draftForEntry', () {
    test('opens ON the in-use saved segment (id + order + full values)',
        () {
      final origin = MappingSegment(
        id: 42,
        activeSeq: 7,
        action: MappingAction.playMedia,
        fgStartMs: 10000,
        fgEndMs: 40000,
        bgStorageId: 'local',
        bgPath: '/m/saved.mp4',
        bgStartMs: 5000,
        bgEndMs: 35000,
        fgPercent: 40,
        bgPercent: 90,
      );

      final d = draftForEntry(
        origin: origin,
        fgPosMs: 20000,
        fgDurMs: 600000,
        bgPosMs: 15000,
        bgDurMs: 600000,
        bgFile: FileItem(
          storageId: 'local',
          name: 'live.mp4',
          uri: 'file:///m/live.mp4',
          path: const ['m', 'live.mp4'],
        ),
      )!;

      expect(d.editingId, 42);
      expect(d.hasOrigin, isTrue);
      expect(d.activeSeq, 7);
      expect(d.bgPath, '/m/saved.mp4');
      expect(d.fgPercent, 40);
      expect(d.bgPercent, 90);
      // The saved span is kept (clamped), not re-seeded from the playhead.
      expect(d.span.fgStartMs, 10000);
      expect(d.span.fgEndMs, 40000);
    });

    test('falls back to a fresh seed when no segment is in use', () {
      final d = draftForEntry(
        origin: null,
        fgPosMs: 10000,
        fgDurMs: 600000,
        bgPosMs: 40000,
        bgDurMs: 600000,
        bgFile: FileItem(
          storageId: 'local',
          name: 'live.mp4',
          uri: 'file:///m/live.mp4',
          path: const ['m', 'live.mp4'],
        ),
      )!;

      expect(d.editingId, 0);
      expect(d.hasOrigin, isFalse);
      expect(d.bgPath, 'm/live.mp4');
      expect(d.span.bgOffsetMs, 30000);
    });
  });
}
