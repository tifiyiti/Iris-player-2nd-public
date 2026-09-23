import 'package:flutter_test/flutter_test.dart';
import 'package:iris/store/use_scrub_drag_store.dart';

/// The single-owner scrub state replaced two latch-prone bare booleans.
/// These tests pin the ownership semantics that make a lost gesture harmless.
void main() {
  group('ScrubDragStore', () {
    test('starts idle', () {
      final store = ScrubDragStore();
      expect(store.state.isScrubbing, isFalse);
      expect(store.state.isHolding, isFalse);
      expect(store.state.any, isFalse);
    });

    test('beginSeek marks scrubbing AND holding', () {
      final store = ScrubDragStore()..beginSeek('a');
      expect(store.state.isScrubbing, isTrue);
      expect(store.state.isHolding, isTrue);
      expect(store.state.any, isTrue);
    });

    test('beginHold keeps the completion suppression without claiming a scrub', () {
      final store = ScrubDragStore()..beginHold('a');
      expect(store.state.isHolding, isTrue);
      expect(store.state.isScrubbing, isFalse);
    });

    test('begin/end are idempotent', () {
      final store = ScrubDragStore()
        ..beginSeek('a')
        ..beginSeek('a');
      expect(store.state.seekOwners, <String>{'a'});
      store
        ..endSeek('a')
        ..endSeek('a');
      expect(store.state.isScrubbing, isFalse);
    });

    test('ending an unknown owner is a no-op', () {
      final store = ScrubDragStore()..beginSeek('a');
      store.endSeek('b');
      expect(store.state.isScrubbing, isTrue);
    });

    test('owners are isolated (one teardown never clobbers another)', () {
      final store = ScrubDragStore()
        ..beginSeek('a')
        ..beginSeek('b');
      store.endSeek('a');
      expect(store.state.isScrubbing, isTrue,
          reason: 'b must keep its session');
      store.endSeek('b');
      expect(store.state.isScrubbing, isFalse);
    });

    test('seek and hold sessions coexist independently', () {
      final store = ScrubDragStore()
        ..beginSeek('a')
        ..beginHold('b');
      store.endSeek('a');
      expect(store.state.isScrubbing, isFalse);
      expect(store.state.isHolding, isTrue, reason: 'the hold is still down');
      store.endHold('b');
      expect(store.state.isHolding, isFalse);
    });

    test('resetAll drops every session (latch-proof teardown backstop)', () {
      final store = ScrubDragStore()
        ..beginSeek('a')
        ..beginHold('b')
        ..resetAll();
      expect(store.state.any, isFalse);
      expect(store.state.seekOwners, isEmpty);
      expect(store.state.holdOwners, isEmpty);
    });
  });
}
