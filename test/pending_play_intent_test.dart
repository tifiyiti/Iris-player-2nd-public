import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/scenario_playback/actions/pending_play_intent.dart';

/// 「待播意图」生命周期：扫描间隙保存的播放参数，在扫描完成后被恢复。
///
/// 覆盖三类行为（计划方案 A）：
/// - [PendingPlayIntent] 可以保存 / 清空。
/// - 扫描完成后持有者会调用 `resume` 复现那次被中断的播放。
/// - 确认后意图被清空（避免重复消费）。
void main() {
  group('PendingPlayIntentHolder', () {
    test('默认无待播意图', () {
      final holder = PendingPlayIntentHolder();
      expect(holder.pending, isNull);
    });

    test('保存意图后可读取', () {
      final holder = PendingPlayIntentHolder();
      var resumed = false;
      holder.set(PendingPlayIntent(
        resume: () async => resumed = true,
      ));
      expect(holder.pending, isNotNull);
      expect(resumed, isFalse);
    });

    test('扫描完成恢复：调用 resume 复现原播放', () async {
      final holder = PendingPlayIntentHolder();
      var resumed = false;
      holder.set(PendingPlayIntent(
        resume: () async => resumed = true,
      ));

      final intent = holder.pending;
      expect(intent, isNotNull);
      await intent!.resume();

      expect(resumed, isTrue);
    });

    test('确认后清空，避免重复消费', () {
      final holder = PendingPlayIntentHolder();
      holder.set(PendingPlayIntent(
        resume: () async {},
      ));
      expect(holder.pending, isNotNull);

      holder.clear();
      expect(holder.pending, isNull);
    });

    test('清空后再次扫描完成不再恢复', () async {
      final holder = PendingPlayIntentHolder();
      var resumed = false;
      holder.set(PendingPlayIntent(
        resume: () async => resumed = true,
      ));
      holder.clear();

      expect(holder.pending, isNull);
      expect(resumed, isFalse);
    });

    test('连续两次待播只保留最近一次（覆盖旧意图）', () async {
      final holder = PendingPlayIntentHolder();
      var firstResumed = false;
      var secondResumed = false;
      holder.set(PendingPlayIntent(
        resume: () async => firstResumed = true,
      ));
      holder.set(PendingPlayIntent(
        resume: () async => secondResumed = true,
      ));

      final intent = holder.pending;
      expect(intent, isNotNull);
      await intent!.resume();

      // 只有最新的意图被恢复；旧的已被覆盖。
      expect(firstResumed, isFalse);
      expect(secondResumed, isTrue);
    });
  });
}