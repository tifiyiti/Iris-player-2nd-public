import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/search/store/use_media_lib_search_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MediaLibSearchStore history (F-009 / F-010)', () {
    test('addHistory dedupes, keeps MRU order, caps at 50', () async {
      final store = MediaLibSearchStore();
      await store.initialized;
      for (var i = 0; i < 55; i++) {
        await store.addHistory('q$i');
      }
      expect(store.state.history.length, 50);
      expect(store.state.history.first, 'q54');
      expect(store.state.history.contains('q0'), isFalse);

      // Re-adding an existing query moves it to the front, no duplicate.
      await store.addHistory('q54');
      expect(store.state.history.length, 50);
      expect(store.state.history.first, 'q54');
      expect(store.state.history.where((h) => h == 'q54').length, 1);
      await store.dispose();
    });

    test('blank query is not recorded', () async {
      final store = MediaLibSearchStore();
      await store.initialized;
      await store.addHistory('   ');
      expect(store.state.history, isEmpty);
      await store.dispose();
    });

    test('bumpHistory moves an existing entry to the front (v4-D6)', () async {
      final store = MediaLibSearchStore();
      await store.initialized;
      await store.addHistory('a');
      await store.addHistory('b');
      await store.bumpHistory('a');
      expect(store.state.history, ['a', 'b']);
      await store.dispose();
    });

    test('bumpHistory on an unknown entry records it (MRU first)', () async {
      final store = MediaLibSearchStore();
      await store.initialized;
      await store.addHistory('a');
      await store.bumpHistory('new');
      expect(store.state.history, ['new', 'a']);
      await store.dispose();
    });

    test('clearHistory empties the list (Q3 / v6-D5)', () async {
      final store = MediaLibSearchStore();
      await store.initialized;
      await store.addHistory('a');
      await store.clearHistory();
      expect(store.state.history, isEmpty);
      await store.dispose();
    });
  });
}
