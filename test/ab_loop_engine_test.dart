import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app_shutdown.dart';
import 'package:iris/features/windows/desktop_keyboard/controller/ab_loop_engine.dart';
import 'package:iris/features/windows/desktop_keyboard/store/ab_loop_state.dart';
import 'package:iris/features/windows/desktop_keyboard/store/ab_loop_store.dart';
import 'package:iris/models/player.dart';

MediaPlayer _fakePlayer(List<Duration> seekLog, {Duration pos = Duration.zero}) =>
    MediaPlayer(
      isInitializing: false,
      isPlaying: true,
      externalSubtitles: const [],
      position: pos,
      duration: const Duration(minutes: 10),
      buffer: Duration.zero,
      width: 0,
      height: 0,
      saveProgress: () async {},
      play: () async {},
      pause: () async {},
      backward: (_) async {},
      forward: (_) async {},
      stepBackward: () async {},
      stepForward: () async {},
      seek: (d) async => seekLog.add(d),
    );

AbLoopState _state() => useAbLoopStore().state;

void main() {
  setUp(() {
    useAbLoopStore().apply(const AbLoopState());
  });

  tearDown(AppShutdown.reset);

  group('AbLoopEngine lifecycle binding', () {
    test('precise stream: seeks back to A once playback crosses B', () async {
      final seeks = <Duration>[];
      final pos = StreamController<Duration>.broadcast(sync: true);
      AbLoopEngine.instance
          .attach(player: _fakePlayer(seeks), precise: pos.stream);

      AbLoopEngine.instance
        ..dispatch(AbEvent.setPointA, const Duration(seconds: 1))
        ..dispatch(AbEvent.setPointB, const Duration(seconds: 5));

      pos.add(const Duration(seconds: 3)); // inside the section
      await Future<void>.delayed(Duration.zero);
      expect(seeks, isEmpty);
      pos.add(const Duration(seconds: 6)); // crossed B
      await Future<void>.delayed(Duration.zero);
      expect(seeks, [const Duration(seconds: 1)]);

      AbLoopEngine.instance.detach();
      await pos.close();
    });

    test('poll source: reads the LIVE getter each tick, not a snapshot', () {
      fakeAsync((async) {
        var livePos = const Duration(seconds: 2);
        final seeks = <Duration>[];
        AbLoopEngine.instance.attach(
          player: _fakePlayer(seeks),
          pollSource: () => livePos,
        );

        AbLoopEngine.instance
          ..dispatch(AbEvent.setPointA, const Duration(seconds: 1))
          ..dispatch(AbEvent.setPointB, const Duration(seconds: 5));

        // Advance past B via the mutable closure — impossible with a frozen
        // wrapper field; proves the poll re-reads live state every tick.
        async.elapse(const Duration(milliseconds: 260));
        expect(seeks, isEmpty);
        livePos = const Duration(seconds: 7);
        async.elapse(const Duration(milliseconds: 260));
        expect(seeks, [const Duration(seconds: 1)]);

        AbLoopEngine.instance.detach();
      });
    });

    test('detach cancels the subscription and wipes stale points', () async {
      final seeks = <Duration>[];
      final pos = StreamController<Duration>.broadcast(sync: true);
      AbLoopEngine.instance
          .attach(player: _fakePlayer(seeks), precise: pos.stream);
      AbLoopEngine.instance
        ..dispatch(AbEvent.setPointA, const Duration(seconds: 1))
        ..dispatch(AbEvent.setPointB, const Duration(seconds: 5))
        ..detach();

      expect(_state(), const AbLoopState()); // points + enabled wiped

      pos.add(const Duration(seconds: 6)); // zombie event after detach
      await Future<void>.delayed(Duration.zero);
      expect(seeks, isEmpty);
      await pos.close();
    });

    test('poll timer stops firing after detach', () {
      fakeAsync((async) {
        final seeks = <Duration>[];
        var livePos = const Duration(seconds: 9);
        AbLoopEngine.instance.attach(
          player: _fakePlayer(seeks),
          pollSource: () => livePos,
        );
        AbLoopEngine.instance
          ..dispatch(AbEvent.setPointA, const Duration(seconds: 1))
          ..dispatch(AbEvent.setPointB, const Duration(seconds: 5))
          ..detach();

        async.elapse(const Duration(seconds: 2));
        expect(seeks, isEmpty); // dangling poll would storm-seek here
      });
    });
  });

  group('AbLoopEngine degenerate-loop guard', () {
    test('A == B never triggers a seek even if state was crafted so', () async {
      final seeks = <Duration>[];
      final pos = StreamController<Duration>.broadcast(sync: true);
      AbLoopEngine.instance
          .attach(player: _fakePlayer(seeks), precise: pos.stream);
      useAbLoopStore().apply(const AbLoopState(
        pointA: Duration(seconds: 2),
        pointB: Duration(seconds: 2),
        enabled: true,
      ));

      pos.add(const Duration(seconds: 2));
      await Future<void>.delayed(Duration.zero);
      pos.add(const Duration(seconds: 3));
      await Future<void>.delayed(Duration.zero);
      expect(seeks, isEmpty); // zero-length loop must not seek-storm

      AbLoopEngine.instance.detach();
      await pos.close();
    });
  });

  group('AbLoopEngine shutdown fence', () {
    test('a tick during shutdown never seeks into a disposing player',
        () async {
      final seeks = <Duration>[];
      final pos = StreamController<Duration>.broadcast(sync: true);
      AbLoopEngine.instance
          .attach(player: _fakePlayer(seeks), precise: pos.stream);
      useAbLoopStore().apply(const AbLoopState(
        pointA: Duration(seconds: 1),
        pointB: Duration(seconds: 5),
        enabled: true,
      ));

      // Accepting a close latches the fence (sticky until reset below).
      AppShutdown.configure(destroy: () async {});
      unawaited(AppShutdown.run());
      await Future<void>.delayed(Duration.zero);
      expect(AppShutdown.isActive, isTrue);

      pos.add(const Duration(seconds: 6)); // crossed B — would seek
      await Future<void>.delayed(Duration.zero);

      expect(seeks, isEmpty,
          reason: 'detach() rides a cleanup a window close never runs, so '
              'this tick can outlive the player');

      AbLoopEngine.instance.detach();
      await pos.close();
    });
  });

  group('abReduce degenerate bounds', () {
    test('setPointB at or before A is ignored (no zero-length loop)', () {
      var s = abReduce(const AbLoopState(), AbEvent.setPointA,
          const Duration(seconds: 5));
      s = abReduce(s, AbEvent.setPointB, const Duration(seconds: 5));
      expect(s.pointB, isNull);
      expect(s.enabled, isFalse);

      s = abReduce(s, AbEvent.setPointB, const Duration(seconds: 4));
      expect(s.pointB, isNull);
      expect(s.enabled, isFalse);

      s = abReduce(s, AbEvent.setPointB, const Duration(seconds: 6));
      expect(s.pointB, const Duration(seconds: 6));
      expect(s.enabled, isTrue);
    });
  });
}
