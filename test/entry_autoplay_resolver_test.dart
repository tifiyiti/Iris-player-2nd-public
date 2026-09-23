import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/meta_settings/engine/playback_resume.dart';
import 'package:iris/models/store/app_state.dart';

/// Custom-entry autoplay policy: cold launches follow the user's
/// resume-on-startup policy (same as the default icon), warm launches preserve
/// the live player's current play intent. A shortcut must never turn a paused
/// session into a playing one.
void main() {
  group('resolveEntryAutoplay', () {
    test('cold start follows resumeOnStartup=true → plays', () {
      const state = AppState(resumeOnStartup: true, autoPlay: false);
      expect(
        resolveEntryAutoplay(state, coldStart: true, metadataEnabled: true),
        isTrue,
      );
    });

    test('cold start follows resumeOnStartup=false → stays paused', () {
      const state = AppState(resumeOnStartup: false, autoPlay: true);
      expect(
        resolveEntryAutoplay(state, coldStart: true, metadataEnabled: true),
        isFalse,
      );
    });

    test('cold start degrades to true when metadata unavailable', () {
      const state = AppState(resumeOnStartup: false, autoPlay: false);
      expect(
        resolveEntryAutoplay(state, coldStart: true, metadataEnabled: false),
        isTrue,
      );
    });

    test('warm start preserves a paused player', () {
      const state = AppState(autoPlay: false, resumeOnStartup: true);
      expect(
        resolveEntryAutoplay(state, coldStart: false, metadataEnabled: true),
        isFalse,
      );
    });

    test('warm start preserves a playing player', () {
      const state = AppState(autoPlay: true, resumeOnStartup: false);
      expect(
        resolveEntryAutoplay(state, coldStart: false, metadataEnabled: true),
        isTrue,
      );
    });
  });
}
