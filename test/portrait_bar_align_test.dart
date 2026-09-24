import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/pages/player/control_bar/control_bar_layout/portrait_bar_align.dart';

/// Mapping guards for the phone-PORTRAIT bottom bar: `center` must reproduce
/// the pre-238d47c2 look per group — the playback rows SPREAD (`spaceEvenly`)
/// while the shrink-wrapped 副音 block is CENTRED as a whole.
void main() {
  group('portrait playback rows', () {
    test('left packs to the start edge', () {
      expect(portraitPlaybackRowAlign(PortraitBarAlign.left),
          MainAxisAlignment.start);
    });

    test('center reproduces the pre-238d47c2 spread (spaceEvenly)', () {
      expect(portraitPlaybackRowAlign(PortraitBarAlign.center),
          MainAxisAlignment.spaceEvenly);
    });

    test('right packs to the end edge', () {
      expect(portraitPlaybackRowAlign(PortraitBarAlign.right),
          MainAxisAlignment.end);
    });
  });

  group('sub-audio block position', () {
    test('maps to the three whole-block alignments', () {
      expect(portraitSubAudioBlockAlign(PortraitBarAlign.left),
          Alignment.centerLeft);
      expect(portraitSubAudioBlockAlign(PortraitBarAlign.center),
          Alignment.center);
      expect(portraitSubAudioBlockAlign(PortraitBarAlign.right),
          Alignment.centerRight);
    });
  });

  group('sub-audio internal wrap', () {
    test('center stays a true centre (never spaceEvenly)', () {
      expect(portraitSubAudioWrapAlign(PortraitBarAlign.left),
          MainAxisAlignment.start);
      expect(portraitSubAudioWrapAlign(PortraitBarAlign.center),
          MainAxisAlignment.center);
      expect(portraitSubAudioWrapAlign(PortraitBarAlign.right),
          MainAxisAlignment.end);
    });
  });
}
