import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/osd/model/osd_entry.dart';
import 'package:iris/features/osd/store/osd_store.dart';

void main() {
  group('OsdStore', () {
    test('show sets entry and hides after duration', () {
      fakeAsync((async) {
        final store = OsdStore();
        const entry = OsdEntry(line1: 'Volume', line2: '50%');
        store.show(entry, duration: const Duration(milliseconds: 2000));
        expect(store.state, entry);
        async.elapse(const Duration(milliseconds: 1999));
        expect(store.state, entry);
        async.elapse(const Duration(milliseconds: 1));
        expect(store.state, isNull);
      });
    });

    test('second show resets timer (no dangling timer)', () {
      fakeAsync((async) {
        final store = OsdStore();
        const a = OsdEntry(line1: 'Volume', line2: '50%');
        const b = OsdEntry(line1: 'Volume', line2: '51%');
        store.show(a, duration: const Duration(milliseconds: 2000));
        async.elapse(const Duration(milliseconds: 1000));
        store.show(b, duration: const Duration(milliseconds: 2000));
        // a's timer should have been cancelled — b survives past 2000 from first show
        async.elapse(const Duration(milliseconds: 1000));
        expect(store.state, b);
        async.elapse(const Duration(milliseconds: 1000));
        expect(store.state, isNull);
      });
    });

    test('hide cancels timer and clears immediately', () {
      fakeAsync((async) {
        final store = OsdStore();
        const entry = OsdEntry(line1: 'Seek', line2: '+5s');
        store.show(entry, duration: const Duration(milliseconds: 2000));
        expect(store.state, isNotNull);
        store.hide();
        expect(store.state, isNull);
        async.elapse(const Duration(milliseconds: 3000));
        expect(store.state, isNull);
      });
    });
  });
}
