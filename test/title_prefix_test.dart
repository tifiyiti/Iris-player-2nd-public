import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/tag_play/playback/tag_play_controller.dart';
import 'package:iris/pages/player/title_prefix.dart';

void main() {
  group('resolveQueuePrefix', () {
    test('tag view wins over every other source', () {
      final tag = const TagViewStatus(index: 3, count: 25, tagName: '喜欢');
      expect(
        resolveQueuePrefix(
          tagView: tag,
          scenarioPos: (index: 99, count: 999),
          isQueryMode: true,
          queryVirtualPos: 0,
          queryTotalCount: 50,
          queueLength: 1,
          currentQueueIndex: 0,
        ),
        '[3/25]',
      );
    });

    test('scenario effective position when no tag view', () {
      expect(
        resolveQueuePrefix(
          tagView: null,
          scenarioPos: (index: 6, count: 42),
          isQueryMode: false,
          queryVirtualPos: 0,
          queryTotalCount: 0,
          queueLength: 1,
          currentQueueIndex: 0,
        ),
        '[7/42]',
      );
    });

    test('query mode uses the virtual position', () {
      expect(
        resolveQueuePrefix(
          tagView: null,
          scenarioPos: null,
          isQueryMode: true,
          queryVirtualPos: 9,
          queryTotalCount: 30,
          queueLength: 0,
          currentQueueIndex: -1,
        ),
        '[10/30]',
      );
    });

    test('in-memory queue when everything else is absent', () {
      expect(
        resolveQueuePrefix(
          tagView: null,
          scenarioPos: null,
          isQueryMode: false,
          queryVirtualPos: 0,
          queryTotalCount: 0,
          queueLength: 5,
          currentQueueIndex: 2,
        ),
        '[3/5]',
      );
    });

    test('single item still gets [1/1]', () {
      expect(
        resolveQueuePrefix(
          tagView: null,
          scenarioPos: null,
          isQueryMode: false,
          queryVirtualPos: 0,
          queryTotalCount: 0,
          queueLength: 1,
          currentQueueIndex: 0,
        ),
        '[1/1]',
      );
    });

    test('null when nothing meaningful plays', () {
      expect(
        resolveQueuePrefix(
          tagView: null,
          scenarioPos: null,
          isQueryMode: false,
          queryVirtualPos: 0,
          queryTotalCount: 0,
          queueLength: 0,
          currentQueueIndex: -1,
        ),
        isNull,
      );
    });
  });
}