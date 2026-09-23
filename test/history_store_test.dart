import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/progress.dart';
import 'package:iris/models/store/history_state.dart';
import 'package:iris/store/use_history_store.dart';

Progress _p(String id, {int pos = 1000}) => Progress(
      dateTime: DateTime.now(),
      position: Duration(milliseconds: pos),
      duration: const Duration(milliseconds: 10000),
      file: FileItem(name: id, uri: id),
    );

void main() {
  group('HistoryStore.trimHistory', () {
    test('keeps the map unchanged when within the cap', () {
      final map = {'a': _p('a'), 'b': _p('b')};
      expect(HistoryStore.trimHistory(map, 500).keys, ['a', 'b']);
    });

    test('evicts the oldest by insertion order when over the cap', () {
      final map = {
        'a': _p('a'),
        'b': _p('b'),
        'c': _p('c'),
        'd': _p('d'),
        'e': _p('e'),
      };
      expect(HistoryStore.trimHistory(map, 3).keys, ['c', 'd', 'e']);
    });

    test('re-added key keeps its original position (FIFO, not LRU)', () {
      final map = {'a': _p('a', pos: 1000), 'b': _p('b')};
      // Re-add of 'a' (as the store's add does) updates in place.
      final next = <String, Progress>{...map, 'a': _p('a', pos: 2000)};
      final out = HistoryStore.trimHistory(next, 2);
      expect(out.keys, ['a', 'b']);
      expect(out['a']!.position, const Duration(milliseconds: 2000));
    });
  });

  group('HistoryStore.normalizeLoaded', () {
    test('clamps a corrupt limit back to the default 500', () {
      final oversized = HistoryState(
        history: {for (var i = 0; i < 600; i++) 'f$i': _p('f$i')},
        maxHistoryRecords: 0,
      );
      final out = HistoryStore.normalizeLoaded(oversized);
      expect(out.maxHistoryRecords, 500);
      expect(out.history.length, 500);
      expect(out.history.containsKey('f0'), isFalse);
      expect(out.history.containsKey('f599'), isTrue);
    });

    test('trims pre-cap oversized history to the persisted limit', () {
      final oversized = HistoryState(
        history: {for (var i = 0; i < 600; i++) 'f$i': _p('f$i')},
        maxHistoryRecords: 400,
      );
      final out = HistoryStore.normalizeLoaded(oversized);
      expect(out.maxHistoryRecords, 400);
      expect(out.history.length, 400);
      expect(out.history.keys.first, 'f200');
    });
  });

  group('HistoryStore.migrateCanonicalKeys', () {
    Progress pUri(String uri) => Progress(
          dateTime: DateTime.now(),
          position: const Duration(milliseconds: 1000),
          duration: const Duration(milliseconds: 10000),
          file: FileItem(name: uri.split(r'\').last, uri: uri),
        );

    test('re-keys legacy getID entries to the canonical progress key', () {
      final legacy = HistoryState(history: {
        r':E:\Movies\a.mp4': pUri(r'E:\Movies\a.mp4'),
        r':E:\Movies\b.mp4': pUri(r'E:\Movies\b.mp4'),
      });
      final out = HistoryStore.migrateCanonicalKeys(legacy);
      expect(out.history.length, 2);
      // Legacy uri-key path (backslashes) maps to the canonical path key.
      expect(out.history.containsKey(':E:/Movies/a.mp4'), isTrue);
      expect(out.history.containsKey(':E:/Movies/b.mp4'), isTrue);
    });

    test('keeps the latest entry when two legacy keys canonicalize the same', () {
      final old = pUri(r'E:\Movies\a.mp4');
      // Force a later dateTime than the first entry.
      final newer = Progress(
        dateTime: old.dateTime.add(const Duration(minutes: 1)),
        position: const Duration(milliseconds: 2000),
        duration: const Duration(milliseconds: 10000),
        file: FileItem(name: 'a.mp4', uri: r'E:\Movies\a.mp4'),
      );
      final legacy = HistoryState(history: {
        ':E:/Movies/a.mp4': old,
        r':E:\Movies\a.mp4': newer,
      });
      final out = HistoryStore.migrateCanonicalKeys(legacy);
      expect(out.history.length, 1);
      expect(out.history[':E:/Movies/a.mp4']!.position,
          const Duration(milliseconds: 2000));
    });

    test('returns the state untouched when nothing changes', () {
      final alreadyCanonical = HistoryState(history: {
        ':E:/Movies/a.mp4': pUri(r'E:\Movies\a.mp4'),
      });
      final out = HistoryStore.migrateCanonicalKeys(alreadyCanonical);
      expect(identical(out, alreadyCanonical), isTrue);
    });
  });

  group('HistoryStore.findById defensive fallback', () {
    test('resolves a canonical key via its legacy raw form', () {
      final store = HistoryStore();
      store.add(Progress(
        dateTime: DateTime.now(),
        position: const Duration(milliseconds: 1000),
        duration: const Duration(milliseconds: 10000),
        file: FileItem(name: 'a.mp4', uri: r'E:\Movies\a.mp4'),
      ));
      // The entry is stored under the canonical key.
      expect(store.findById(':E:/Movies/a.mp4'), isNotNull);
      // A legacy getID-style lookup still resolves via the defensive fallback.
      expect(store.findById(r':E:\Movies\a.mp4'), isNotNull);
    });
  });

  group('HistoryStore add with cap', () {
    test('inserting beyond the default 500 keeps exactly 500, oldest evicted',
        () async {
      final store = HistoryStore();
      await store.initialized;
      for (var i = 0; i < 505; i++) {
        await store.add(_p('file$i'));
      }
      // Keys are FileItem.getID() = '$storageId:$uri' (storageId defaults '').
      final k0 = _p('file0').file.getID();
      final k4 = _p('file4').file.getID();
      final k5 = _p('file5').file.getID();
      final k504 = _p('file504').file.getID();
      expect(store.state.history.length, 500);
      expect(store.state.history.containsKey(k0), isFalse);
      expect(store.state.history.containsKey(k4), isFalse);
      expect(store.state.history.containsKey(k504), isTrue);
      expect(store.state.history.keys.first, k5);
    });

    test('re-adding the same file updates the value without growing',
        () async {
      final store = HistoryStore();
      await store.initialized;
      final ka = _p('a').file.getID();
      final kb = _p('b').file.getID();
      await store.add(_p('a', pos: 1000));
      await store.add(_p('b'));
      await store.add(_p('a', pos: 3000));
      expect(store.state.history.length, 2);
      expect(store.state.history[ka]!.position,
          const Duration(milliseconds: 3000));
      // FIFO: 'a' keeps its original insertion position (index 0).
      expect(store.state.history.keys.toList(), [ka, kb]);
    });
  });
}
