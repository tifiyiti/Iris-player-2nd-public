import 'package:iris/features/tag_play/model/db/repositories/tag_play_repository.dart';
import 'package:iris/utils/logger.dart';

final _log = AreaKeyLog(LogKeys.tagPlay);

/// Ensures the three system-reserved tags exist (临时标记 / 永久收藏 /
/// 副音备选). Reserved tags are owned by the system: they can never be
/// deleted or renamed (repository guards), so — unlike the old deletable
/// "sample tags" — they are re-ensured on every startup instead of being
/// seeded once and never resurrected. Failures never block startup.
abstract final class TagPlayBootstrap {
  static bool _doneInProcess = false;

  /// Test hook: clears the in-process latch so a fresh suite can re-seed.
  static void resetForTests() => _doneInProcess = false;

  static Future<void> ensure(TagPlayRepository repo) async {
    if (_doneInProcess) return;
    try {
      final ensured = await repo.ensureReservedTags();
      _doneInProcess = true;
      _log.i('TagPlayBootstrap: reserved tags ensured '
          '(count=${ensured.length})');
    } catch (e) {
      _log.e('TagPlayBootstrap.ensure failed: $e');
    }
  }
}
