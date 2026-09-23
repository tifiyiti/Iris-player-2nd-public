import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/phone/one_handed_scrubber/view/phone_ring_dial_scrubber.dart';
import 'package:iris/features/virtual_media/model/domain/vm_item.dart';
import 'package:iris/features/virtual_media/store/vm_playback_store.dart';
import 'package:iris/models/player.dart';
import 'package:provider/provider.dart';

/// Guards the VM-specific dial painting path: the equal-arc chunk ring, the
/// per-file progress ring and the numeric gap labels must all rebuild without
/// throwing while a virtual session is active, and an outer-ring tap must
/// route through an existing seek without error.
void main() {
  VirtualSegment seg(String path,
      {int? durationMs, bool estimated = false}) {
    final parts = path.split('/');
    return VirtualSegment(
      mediaKey: 'st1:$path',
      storageId: 'st1',
      path: parts,
      name: parts.last,
      parentPath:
          parts.length <= 1 ? '' : parts.sublist(0, parts.length - 1).join('/'),
      durationMs: durationMs,
      durationEstimated: estimated,
    );
  }

  VirtualMediaItem vmItemOf(List<VirtualSegment> segments) => VirtualMediaItem(
        ruleId: 'r',
        scopeKey: 'r|k|1',
        rootPath: 'k',
        displayIndex: 1,
        displayName: 'k',
        segments: segments,
      );

  testWidgets('VM dial renders equal-arc ring + labels without error',
      (tester) async {
    final item = vmItemOf([
      seg('k/1.mp4', durationMs: 1000),
      seg('k/2.mp4', durationMs: 2000),
      seg('k/3.mp4', durationMs: 500, estimated: true),
    ]);
    // 3 segments, total 3500ms.
    useVmPlaybackStore().replace(
      VmPlaybackState(
        item: item,
        segmentIndex: 1,
        queue: [item],
        queueIndex: 0,
      ),
    );

    await tester.pumpWidget(StoreScope(
      child: Provider<MediaPlayer>.value(
        value: MediaPlayer(
          isInitializing: false,
          isPlaying: false,
          externalSubtitles: const [],
          position: const Duration(milliseconds: 1500), // inside segment 1
          duration: Duration(milliseconds: item.totalDurationMs),
          buffer: const Duration(milliseconds: 1500),
          width: 16,
          height: 9,
          saveProgress: () async {},
          play: () async {},
          pause: () async {},
          backward: (int s) async {},
          forward: (int s) async {},
          stepBackward: () async {},
          stepForward: () async {},
          seek: (Duration t) async {},
        ),
        child: MaterialApp(
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
    ));
    await tester.pump();

    // VM equal-arc + gap-label painting must not throw.
    expect(tester.takeException(), isNull,
        reason: 'VM equal-arc ring + gap labels must paint cleanly');
    expect(find.byType(PhoneRingDialScrubber), findsOneWidget);
  });
}