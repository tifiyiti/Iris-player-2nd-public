import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/windows/desktop_keyboard/controller/potplayer_sequence_map.dart';
import 'package:iris/features/windows/desktop_keyboard/store/key_sequence_buffer_store.dart';

void main() {
  setUp(() => useKeySequenceBufferStore().reset());

  group('KeySequenceBufferStore timer ownership (D3/D4)', () {
    test('auto-closes after the timeout', () {
      fakeAsync((async) {
        final store = useKeySequenceBufferStore();
        store.open();
        expect(store.state.isBuffering, isTrue);
        async.elapse(kSequenceBufferTimeout + const Duration(milliseconds: 10));
        expect(store.state.isBuffering, isFalse);
        expect(store.elapsed, isNull);
      });
    });

    test('second open cancels first timer — no premature timeout (D3)', () {
      fakeAsync((async) {
        final store = useKeySequenceBufferStore();
        store.open(); // t=0
        async.elapse(const Duration(seconds: 1));
        store.close(); // Complete at t=1s (close+perform path)
        store.open(); // t=1s reopen

        async.elapse(const Duration(seconds: 2)); // t=3s — old t=0+3 deadline
        expect(store.state.isBuffering, isTrue,
            reason: 'reopened session must survive the dangling first timer');

        async.elapse(const Duration(seconds: 1, milliseconds: 100)); // t≈4.1s
        expect(store.state.isBuffering, isFalse,
            reason: 'new session must time out on its own deadline');
      });
    });

    test('elapsed is real after open (D4 — R5b reachable)', () {
      fakeAsync((async) {
        final store = useKeySequenceBufferStore();
        store.open();
        expect(store.elapsed, isNotNull);
        expect(store.elapsed! < kSequenceBufferTimeout, isTrue);
        async.elapse(kSequenceBufferTimeout + const Duration(milliseconds: 50));
        // After timeout the store is no longer buffering; elapsed is nulled.
        // Before the timeout a trailing key would see elapsed > timeout and
        // resolveSequence would return Discard (R5b).
        expect(store.state.isBuffering, isFalse);
      });
    });

    test('close cancels pending timer', () {
      fakeAsync((async) {
        final store = useKeySequenceBufferStore();
        store.open();
        store.close();
        expect(store.state.isBuffering, isFalse);
        expect(store.elapsed, isNull);
        async.elapse(kSequenceBufferTimeout + const Duration(seconds: 1));
        expect(store.state.isBuffering, isFalse);
      });
    });
  });
}
