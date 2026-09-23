import 'dart:math' as m;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/background_playback/model/enum/control_target.dart';
import 'package:iris/features/background_playback/store/use_background_playback_store.dart';
import 'package:iris/features/phone/one_handed_scrubber/view/phone_ring_dial_scrubber.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/player.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:provider/provider.dart';
import 'package:zustand/zustand.dart';

/// 仅当前 + 高同步: the dial must clamp every seek into the published bg window
/// (and never roll the foreground past its 100%). The marks themselves are
/// painter-only; this locks the behavioral contract the marks represent.
class _Rec {
  final List<Duration> seeks = <Duration>[];

  MediaPlayer player({required Duration position, required Duration duration}) {
    return MediaPlayer(
      isInitializing: false,
      isPlaying: false,
      externalSubtitles: const [],
      position: position,
      duration: duration,
      buffer: Duration.zero,
      width: 16,
      height: 9,
      saveProgress: () async {},
      play: () async {},
      pause: () async {},
      backward: (int s) async {},
      forward: (int s) async {},
      stepBackward: () async {},
      stepForward: () async {},
      seek: (Duration t) async => seeks.add(t),
    );
  }
}

Widget _harness(_Rec rec,
    {required Duration position, required Duration duration}) {
  return StoreScope(
    child: Provider<MediaPlayer>.value(
      value: rec.player(position: position, duration: duration),
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              height: 210,
              child: PhoneRingDialScrubber(
                showControl: () {},
                color: Colors.white,
                isLeftHanded: false,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Offset _clockPoint(Offset center, double radius, double clockDeg) {
  final double rad = clockDeg * m.pi / 180 - m.pi / 2;
  return center + Offset(radius * m.cos(rad), radius * m.sin(rad));
}

Future<void> _tap(WidgetTester tester, Offset global) async {
  final TestGesture g = await tester.startGesture(global);
  await g.up();
  await tester.pump();
}

Offset _ringCenter(WidgetTester tester) {
  for (final Element e in find
      .descendant(
        of: find.byType(PhoneRingDialScrubber),
        matching: find.byType(GestureDetector),
      )
      .evaluate()) {
    final RenderBox rb = e.renderObject! as RenderBox;
    if ((rb.size.width - rb.size.height).abs() < 0.01 && rb.size.width > 100) {
      return (rb.localToGlobal(Offset.zero) & rb.size).center;
    }
  }
  throw StateError('ring dial square not found');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  tearDown(() => StoreLocator().delete(BackgroundPlaybackStore));

  testWidgets('bg seeks are clamped into the published window', (tester) async {
    final bg = useBackgroundPlaybackStore();
    await bg.initialized;
    bg.set(bg.state.copyWith(
      enabled: true,
      // The seek window only clamps while the gate is open (bg active).
      gateOpen: true,
      controlTarget: ControlTarget.background,
      bgSeekFloorLocalMs: 600000, // 10 min
      bgSeekCeilingLocalMs: 1200000, // 20 min
    ));
    await useAppStore().updateRingDialHeightPct(1.0);
    await useAppStore().updateRingDialRingSlotT(0.85);

    final rec = _Rec();
    // 36 min → 11 blocks (capped), so the chunk ring is visible/hittable.
    const Duration dur = Duration(minutes: 36);
    await tester.pumpWidget(_harness(rec,
        position: const Duration(minutes: 15), duration: dur));
    await tester.pumpAndSettle();

    final Offset center = _ringCenter(tester);

    // Inner (chunk) ring, first slot ≈ 0% → clamped UP to the floor.
    await _tap(tester, _clockPoint(center, 79.5, 28.7));
    await tester.pump();
    expect(rec.seeks, isNotEmpty);
    expect(rec.seeks.last, greaterThanOrEqualTo(const Duration(minutes: 10)));

    // Inner ring, last slot ≈ 100% → clamped DOWN to the ceiling.
    await _tap(tester, _clockPoint(center, 79.5, 325));
    await tester.pump();
    expect(rec.seeks.last, lessThanOrEqualTo(const Duration(minutes: 20)));
  });
}
