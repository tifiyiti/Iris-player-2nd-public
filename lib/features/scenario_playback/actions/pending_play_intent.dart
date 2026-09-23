import 'package:flutter/foundation.dart';

/// 「待播意图」——一次被「先扫描」这一异步工作打断的播放请求。
///
/// 门控（`ensureDirsScanned`）遇到目录未完整扫描时，用户选「立即完整扫描」。
/// 扫描会异步进行，期间必须记住"用户本来要做什么"。把那次播放的参数
/// 封装成 [PendingPlayIntent] 保存下来，扫描完成后再弹确认恢复。
///
/// 纯内存、不持久化：进程被杀后不该自动续播（否则 UI 层会出现用户在重启后
/// 才遇到的一次预期之外的播放），也避免残留参数在重启后被错误消费。扫描是
/// 同一进程内的状态流转，内存持有完全够用。
@immutable
class PendingPlayIntent {
  const PendingPlayIntent({
    required this.resume,
  });

  /// 复现那次被中断的播放。调用方用它传入的已捕获参数重新执行 override /
  /// append，等价于用户在扫描完成后"再点一次"。
  final Future<void> Function() resume;
}

/// 「待播意图」的进程内持有者。
///
/// 单例由 [usePendingPlayIntentHolder] 提供；测试可直接构造。只保存最近一次
/// 待播（新的 override 会覆盖旧的）。扫描完成后消费并清空，避免重复触发。
class PendingPlayIntentHolder extends ChangeNotifier {
  PendingPlayIntent? _pending;

  /// 当前待播意图；无时返回 null。
  PendingPlayIntent? get pending => _pending;

  /// 保存一次待播意图（覆盖之前的）。
  void set(PendingPlayIntent intent) {
    _pending = intent;
    notifyListeners();
  }

  /// 消费/清空当前待播意图。扫描完成恢复播放成功后调用。
  void clear() {
    if (_pending == null) return;
    _pending = null;
    notifyListeners();
  }
}

/// 全局唯一待播意图持有者（进程内单例）。
PendingPlayIntentHolder usePendingPlayIntentHolder() =>
    _globalPendingPlayIntentHolder;

final PendingPlayIntentHolder _globalPendingPlayIntentHolder =
    PendingPlayIntentHolder();