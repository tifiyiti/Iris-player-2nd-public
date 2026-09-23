import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/app_identity/services/pinned_refresh_policy.dart';

void main() {
  group('PinnedRefreshPolicy.shouldQuery', () {
    const base = PinnedRefreshPolicy.throttleMs + 1000;

    bool query({
      bool isRefreshing = false,
      bool isAndroid = true,
      bool isRouteCurrent = true,
      bool hasEntries = true,
      int nowMs = base,
      int lastQueryMs = 0,
      bool force = false,
    }) =>
        PinnedRefreshPolicy.shouldQuery(
          isRefreshing: isRefreshing,
          isAndroid: isAndroid,
          isRouteCurrent: isRouteCurrent,
          hasEntries: hasEntries,
          nowMs: nowMs,
          lastQueryMs: lastQueryMs,
          force: force,
        );

    test('first query passes (lastQueryMs zero)', () {
      expect(query(), isTrue);
    });

    test('resumed query inside the throttle window is skipped', () {
      expect(
        query(nowMs: 1500, lastQueryMs: 1000),
        isFalse,
        reason: 'Binder IPC must not fire on every resume bounce',
      );
    });

    test('resumed query past the throttle window passes', () {
      expect(
        query(nowMs: 1000 + PinnedRefreshPolicy.throttleMs, lastQueryMs: 1000),
        isTrue,
      );
    });

    test('force bypasses the throttle window', () {
      expect(
        query(nowMs: 1500, lastQueryMs: 1000, force: true),
        isTrue,
        reason: 'mount / manual refresh / editor return always re-query',
      );
    });

    test('in-flight query is never duplicated', () {
      expect(query(isRefreshing: true, force: true), isFalse);
    });

    test('non-Android hosts never query', () {
      expect(query(isAndroid: false, force: true), isFalse);
    });

    test('obscured route (editor on top) never queries', () {
      expect(query(isRouteCurrent: false, force: true), isFalse);
    });

    test('empty entry list never queries', () {
      expect(query(hasEntries: false, force: true), isFalse);
    });
  });

  group('PinnedRefreshPolicy.isSameSet', () {
    test('equal sets in different order match', () {
      expect(
        PinnedRefreshPolicy.isSameSet({'a', 'b'}, {'b', 'a'}),
        isTrue,
      );
    });

    test('different sizes differ', () {
      expect(PinnedRefreshPolicy.isSameSet({'a'}, {'a', 'b'}), isFalse);
    });

    test('same size but different members differ', () {
      expect(PinnedRefreshPolicy.isSameSet({'a'}, {'b'}), isFalse);
    });

    test('two empty sets match (no rebuild on empty resume)', () {
      expect(PinnedRefreshPolicy.isSameSet(<String>{}, <String>{}), isTrue);
    });
  });
}
