import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/services/editor_audition_logic.dart';

/// The APB editor's live-audition decision: the foreground is always the
/// transport master, and the 副音 joins ONLY while the playhead sits inside the
/// edited span [A,B] — the region where the 1:1 alignment maps real bg content.
void main() {
  EditorAuditionAction resolve({
    bool isPlayMedia = true,
    bool bgReady = true,
    bool fgPlaying = true,
    bool bgPlaying = false,
    int fgPosMs = 5000,
    int spanStartMs = 1000,
    int spanEndMs = 10000,
  }) =>
      resolveEditorAudition(
        isPlayMedia: isPlayMedia,
        bgReady: bgReady,
        fgPlaying: fgPlaying,
        bgPlaying: bgPlaying,
        fgPosMs: fgPosMs,
        spanStartMs: spanStartMs,
        spanEndMs: spanEndMs,
      );

  test('starts 副音 when a playing playhead enters [A,B]', () {
    expect(resolve(), EditorAuditionAction.startBg);
  });

  test('leaves an already-playing 副音 alone inside [A,B]', () {
    expect(resolve(bgPlaying: true), EditorAuditionAction.none);
  });

  test('stops 副音 before A (bg progress would be negative)', () {
    expect(
      resolve(fgPosMs: 999, bgPlaying: true),
      EditorAuditionAction.stopBg,
    );
  });

  test('stops 副音 after B (bg content exhausted)', () {
    expect(
      resolve(fgPosMs: 10001, bgPlaying: true),
      EditorAuditionAction.stopBg,
    );
  });

  test('A and B are inclusive bounds', () {
    expect(resolve(fgPosMs: 1000), EditorAuditionAction.startBg);
    expect(resolve(fgPosMs: 10000), EditorAuditionAction.startBg);
  });

  test('never plays 副音 while the foreground is paused', () {
    expect(
      resolve(fgPlaying: false, bgPlaying: true),
      EditorAuditionAction.stopBg,
    );
    expect(resolve(fgPlaying: false), EditorAuditionAction.none);
  });

  test('silence drafts never audition 副音', () {
    expect(
      resolve(isPlayMedia: false, bgPlaying: true),
      EditorAuditionAction.stopBg,
    );
    expect(resolve(isPlayMedia: false), EditorAuditionAction.none);
  });

  test('an unloaded 副音 (no duration) never starts', () {
    expect(
      resolve(bgReady: false, bgPlaying: true),
      EditorAuditionAction.stopBg,
    );
    expect(resolve(bgReady: false), EditorAuditionAction.none);
  });
}
