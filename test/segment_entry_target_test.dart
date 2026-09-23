import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/model/domain/background_mapping.dart';
import 'package:iris/features/background_playback/model/enum/mapping_action.dart';
import 'package:iris/features/background_playback/resolver/segment_entry_target.dart';

MappingSegment _seg(
  int id,
  int fgStart,
  int fgEnd, {
  int activeSeq = 0,
  bool isActive = true,
}) =>
    MappingSegment(
      id: id,
      action: MappingAction.playMedia,
      fgStartMs: fgStart,
      fgEndMs: fgEnd,
      bgStorageId: 'local',
      bgPath: 'b.mp4',
      bgStartMs: fgStart,
      bgEndMs: fgEnd,
      activeSeq: activeSeq,
      isActive: isActive,
    );

void main() {
  const int fg10m = 600000;
  const int bg1m = 60000;

  group('nearestActiveSegment', () {
    test('picks the nearest interval, before or after the playhead', () {
      final segments = [_seg(1, 0, 30000), _seg(2, 500000, 530000)];
      expect(nearestActiveSegment(segments, 100000)!.id, 1);
      expect(nearestActiveSegment(segments, 490000)!.id, 2);
    });

    test('ignores disabled segments', () {
      final segments = [
        _seg(1, 0, 30000),
        _seg(2, 500000, 530000, isActive: false),
      ];
      expect(nearestActiveSegment(segments, 490000)!.id, 1);
      expect(nearestActiveSegment(segments, 100000), isNotNull);
    });

    test('equal distance breaks on the higher activation order', () {
      final segments = [
        _seg(1, 100000, 130000, activeSeq: 1),
        _seg(2, 200000, 230000, activeSeq: 5),
      ];
      // 165000 is 35000 from both; the later-activated segment wins.
      expect(nearestActiveSegment(segments, 165000)!.id, 2);
    });

    test('no active segment returns null', () {
      expect(nearestActiveSegment(const [], 1000), isNull);
      expect(
        nearestActiveSegment([_seg(1, 0, 1000, isActive: false)], 500),
        isNull,
      );
    });
  });

  group('playheadOutsideSegmentWindow', () {
    test('far past B is outside', () {
      expect(
        playheadOutsideSegmentWindow(
          fgDurMs: fg10m,
          bgDurMs: bg1m,
          zoom: 2,
          pushBg: false,
          fgPosMs: 500000,
          segmentStartMs: 100000,
          segmentEndMs: 130000,
        ),
        isTrue,
      );
    });

    test('far before A is outside', () {
      expect(
        playheadOutsideSegmentWindow(
          fgDurMs: fg10m,
          bgDurMs: bg1m,
          zoom: 2,
          pushBg: false,
          fgPosMs: 0,
          segmentStartMs: 100000,
          segmentEndMs: 130000,
        ),
        isTrue,
      );
    });

    test('inside the segment or its window is not outside', () {
      // W = 120000 → the window around A=100000 spans [10000, 130000].
      expect(
        playheadOutsideSegmentWindow(
          fgDurMs: fg10m,
          bgDurMs: bg1m,
          zoom: 2,
          pushBg: false,
          fgPosMs: 100000,
          segmentStartMs: 100000,
          segmentEndMs: 130000,
        ),
        isFalse,
      );
      expect(
        playheadOutsideSegmentWindow(
          fgDurMs: fg10m,
          bgDurMs: bg1m,
          zoom: 2,
          pushBg: false,
          fgPosMs: 50000,
          segmentStartMs: 100000,
          segmentEndMs: 130000,
        ),
        isFalse,
      );
    });

    test('a span wider than the window falls back to the playhead', () {
      expect(
        playheadOutsideSegmentWindow(
          fgDurMs: fg10m,
          bgDurMs: bg1m,
          zoom: 2,
          pushBg: false,
          fgPosMs: 100000,
          segmentStartMs: 0,
          segmentEndMs: 200000,
        ),
        isFalse,
      );
    });

    test('unknown durations are never "far"', () {
      expect(
        playheadOutsideSegmentWindow(
          fgDurMs: 0,
          bgDurMs: bg1m,
          zoom: 2,
          pushBg: false,
          fgPosMs: 500000,
          segmentStartMs: 100000,
          segmentEndMs: 130000,
        ),
        isFalse,
      );
      expect(
        playheadOutsideSegmentWindow(
          fgDurMs: fg10m,
          bgDurMs: 0,
          zoom: 2,
          pushBg: false,
          fgPosMs: 500000,
          segmentStartMs: 100000,
          segmentEndMs: 130000,
        ),
        isFalse,
      );
    });
  });
}
