import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/store/use_playback_progress_store.dart';

void main() {
  group('PlaybackProgressStore', () {
    test('starts empty and update adds entries', () {
      final store = PlaybackProgressStore();
      expect(store.state, isEmpty);

      store.update('a', 1000, 10000);
      store.update('b', 2000, 10000);
      expect(store.state['a'], (1000, 10000));
      expect(store.state['b'], (2000, 10000));
    });

    test('update overwrites the value for the same fileId', () {
      final store = PlaybackProgressStore();
      store.update('a', 1000, 10000);
      store.update('a', 5000, 10000);
      expect(store.state['a'], (5000, 10000));
      expect(store.state.length, 1);
    });
  });
}
