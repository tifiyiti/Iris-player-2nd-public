import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/windows/desktop_keyboard/controller/speed_reset_toggle.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_app_store.dart';

void main() {
  group('resolveSpeedResetToggle', () {
    test('parks a custom rate at 1.0 and remembers it', () {
      final (:rate, :memory) = resolveSpeedResetToggle(2.0, 1.0);
      expect(rate, 1.0);
      expect(memory, 2.0);
    });

    test('restores the remembered rate on a second press', () {
      final (:rate, :memory) = resolveSpeedResetToggle(1.0, 2.5);
      expect(rate, 2.5);
      expect(memory, 2.5);
    });

    test('is a no-op when never customized', () {
      final (:rate, :memory) = resolveSpeedResetToggle(1.0, 1.0);
      expect(rate, 1.0);
      expect(memory, 1.0);
    });

    test('re-parking overwrites the memory with the newer rate', () {
      final first = resolveSpeedResetToggle(2.0, 1.0);
      expect(first.memory, 2.0);
      // User pressed C twice more: 1.0 -> 1.1 -> ... -> 3.0, then Z again.
      final second = resolveSpeedResetToggle(3.0, first.memory);
      expect(second.rate, 1.0);
      expect(second.memory, 3.0);
    });
  });

  group('AppStore.applyRateChange', () {
    test('any explicit non-1.0 rate refreshes the restore memory', () {
      final next = AppStore.applyRateChange(
          const AppState(rate: 1.0, rateBeforeReset: 2.0), 1.5);
      expect(next.rate, 1.5);
      expect(next.rateBeforeReset, 1.5);
    });

    test('setting the same non-1.0 rate keeps the memory stable', () {
      final next = AppStore.applyRateChange(
          const AppState(rate: 2.0, rateBeforeReset: 4.0), 4.0);
      expect(next.rateBeforeReset, 4.0);
    });

    test('returning to 1.0 leaves the memory untouched', () {
      final next = AppStore.applyRateChange(
          const AppState(rate: 3.3, rateBeforeReset: 3.3), 1.0);
      expect(next.rate, 1.0);
      expect(next.rateBeforeReset, 3.3);
    });
  });
}
