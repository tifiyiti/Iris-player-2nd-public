import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/scenario_playback/store/playback_scenario_store_state.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';

/// Store subclass that never touches secure storage / the DB and counts save()
/// calls so the per-surface UI pref setters can be unit-tested in isolation.
class _TestPlaybackScenarioStore extends PlaybackScenarioStore {
  int saveCount = 0;

  @override
  Future<PlaybackScenarioStoreState?> load() async => null;

  @override
  Future<void> save(PlaybackScenarioStoreState s) async {
    saveCount++;
  }

  @override
  void onReady() {}
}

void main() {
  group('PlaybackScenarioStore per-surface UI prefs defaults', () {
    test('defaults: 50 / 50 / true / 100', () {
      final store = _TestPlaybackScenarioStore();
      expect(store.state.playingScenarioQueuePageSize, 50);
      expect(store.state.scenarioPreviewQueuePageSize, 50);
      expect(store.state.scenarioPreviewStayOnTap, isTrue);
      expect(store.state.scenarioManagePageSize, 100);
    });
  });

  group('PlaybackScenarioStore per-surface UI pref setters', () {
    test('updatePlayingScenarioQueuePageSize updates state and saves', () async {
      final store = _TestPlaybackScenarioStore();
      await store.updatePlayingScenarioQueuePageSize(120);
      expect(store.state.playingScenarioQueuePageSize, 120);
      expect(store.saveCount, 1);
    });

    test('updateScenarioPreviewQueuePageSize updates state and saves', () async {
      final store = _TestPlaybackScenarioStore();
      await store.updateScenarioPreviewQueuePageSize(80);
      expect(store.state.scenarioPreviewQueuePageSize, 80);
      expect(store.saveCount, 1);
    });

    test('updateScenarioPreviewStayOnTap toggles and saves', () async {
      final store = _TestPlaybackScenarioStore();
      await store.updateScenarioPreviewStayOnTap(false);
      expect(store.state.scenarioPreviewStayOnTap, isFalse);
      expect(store.saveCount, 1);
    });

    test('updateScenarioManagePageSize updates state and saves', () async {
      final store = _TestPlaybackScenarioStore();
      await store.updateScenarioManagePageSize(200);
      expect(store.state.scenarioManagePageSize, 200);
      expect(store.saveCount, 1);
    });
  });

  group('PlaybackScenarioStoreState serialization', () {
    test('toJson excludes the scenarios mirror', () {
      final state = PlaybackScenarioStoreState();
      final json = state.toJson();
      expect(json.containsKey('scenarios'), isFalse);
    });

    test('fromJson without scenarios key defaults to empty list', () {
      final state = PlaybackScenarioStoreState.fromJson(
        const <String, dynamic>{},
      );
      expect(state.scenarios, isEmpty);
    });

    test('fromJson ignores a stale scenarios key (legacy blob)', () {
      final state = PlaybackScenarioStoreState.fromJson(
        const <String, dynamic>{'scenarios': ['legacy', 'data']},
      );
      expect(state.scenarios, isEmpty);
    });

    test('round-trip preserves the four prefs', () {
      final state = PlaybackScenarioStoreState(
        playingScenarioQueuePageSize: 120,
        scenarioPreviewQueuePageSize: 80,
        scenarioPreviewStayOnTap: false,
        scenarioManagePageSize: 200,
      );
      final restored = PlaybackScenarioStoreState.fromJson(state.toJson());
      expect(restored.playingScenarioQueuePageSize, 120);
      expect(restored.scenarioPreviewQueuePageSize, 80);
      expect(restored.scenarioPreviewStayOnTap, isFalse);
      expect(restored.scenarioManagePageSize, 200);
    });
  });
}
