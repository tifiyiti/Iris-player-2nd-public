import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/engine/background_scope_logic.dart';
import 'package:iris/features/background_playback/model/enum/bg_apply_scope.dart';

/// Activation scope of one 副音 run (作用范围).
///
/// - all        → keeps playing across foreground media switches;
/// - currentOnly→ anchored to one media: leaving pauses, returning resumes;
/// - smart      → a media with a saved 副音 pairing starts 副音, others pause.
///
/// A media the user explicitly closed 副音 for always pauses, whatever the
/// scope.
void main() {
  group('resolveBgScopeOnFgChange', () {
    test('副音 off is a no-op regardless of the scope fields', () {
      expect(
        resolveBgScopeOnFgChange(
          enabled: false,
          applyScope: BgApplyScope.currentOnly,
          anchorKey: 'a',
          newFgKey: 'b',
        ),
        BgScopeAction.none,
      );
      expect(
        resolveBgScopeOnFgChange(
          enabled: false,
          applyScope: BgApplyScope.all,
          anchorKey: null,
          newFgKey: null,
        ),
        BgScopeAction.none,
      );
    });

    test('a null foreground key (no media loaded) is not a switch', () {
      expect(
        resolveBgScopeOnFgChange(
          enabled: true,
          applyScope: BgApplyScope.currentOnly,
          anchorKey: 'a',
          newFgKey: null,
        ),
        BgScopeAction.none,
      );
    });

    test('all keeps playing across foreground media switches', () {
      expect(
        resolveBgScopeOnFgChange(
          enabled: true,
          applyScope: BgApplyScope.all,
          anchorKey: null,
          newFgKey: 'b',
        ),
        BgScopeAction.none,
      );
    });

    test('currentOnly pauses when leaving the anchored media', () {
      expect(
        resolveBgScopeOnFgChange(
          enabled: true,
          applyScope: BgApplyScope.currentOnly,
          anchorKey: 'a',
          newFgKey: 'b',
        ),
        BgScopeAction.pauseBg,
      );
    });

    test('currentOnly resumes when returning to the anchored media', () {
      expect(
        resolveBgScopeOnFgChange(
          enabled: true,
          applyScope: BgApplyScope.currentOnly,
          anchorKey: 'a',
          newFgKey: 'a',
        ),
        BgScopeAction.resumeBg,
      );
    });

    test('currentOnly without an anchor never touches playback', () {
      expect(
        resolveBgScopeOnFgChange(
          enabled: true,
          applyScope: BgApplyScope.currentOnly,
          anchorKey: null,
          newFgKey: 'b',
        ),
        BgScopeAction.none,
      );
    });

    test('smart starts on a media with a saved 副音 pairing', () {
      expect(
        resolveBgScopeOnFgChange(
          enabled: true,
          applyScope: BgApplyScope.smart,
          anchorKey: null,
          newFgKey: 'b',
          newFgHasSavedMapping: true,
        ),
        BgScopeAction.startBg,
      );
    });

    test('smart leaves a new media off when it has no pairing', () {
      expect(
        resolveBgScopeOnFgChange(
          enabled: true,
          applyScope: BgApplyScope.smart,
          anchorKey: null,
          newFgKey: 'b',
          newFgHasSavedMapping: false,
        ),
        BgScopeAction.pauseBg,
      );
    });

    test('smart auto-starts even while 副音 is off', () {
      // The scope observer only ever produces [BgScopeAction.startBg] while the
      // run is enabled; if an enabled run made it a no-op the "已保存副音自动播放"
      // feature could never fire. It must also fire from a cold (disabled) state.
      expect(
        resolveBgScopeOnFgChange(
          enabled: false,
          applyScope: BgApplyScope.smart,
          anchorKey: null,
          newFgKey: 'b',
          newFgHasSavedMapping: true,
        ),
        BgScopeAction.startBg,
      );
    });

    test('smart stays idle while 副音 is off and the media has no pairing', () {
      expect(
        resolveBgScopeOnFgChange(
          enabled: false,
          applyScope: BgApplyScope.smart,
          anchorKey: null,
          newFgKey: 'b',
          newFgHasSavedMapping: false,
        ),
        BgScopeAction.none,
      );
    });

    test('an explicitly closed media pauses whatever the scope', () {
      for (final scope in BgApplyScope.values) {
        expect(
          resolveBgScopeOnFgChange(
            enabled: true,
            applyScope: scope,
            anchorKey: 'b',
            newFgKey: 'b',
            offMediaKeys: const {'b'},
            newFgHasSavedMapping: true,
          ),
          BgScopeAction.pauseBg,
          reason: '$scope must not outrank the per-media off set',
        );
      }
    });
  });

  group('resolveApplyToCurrent (quick-bar apply toggle)', () {
    test('off while 副音 is not running', () {
      expect(
        resolveApplyToCurrent(
          enabled: false,
          applyScope: BgApplyScope.all,
          anchorKey: null,
          offMediaKeys: const <String>{},
          fgKey: 'a',
        ),
        isFalse,
      );
    });

    test('on for all / smart while 副音 runs', () {
      for (final scope in [BgApplyScope.all, BgApplyScope.smart]) {
        expect(
          resolveApplyToCurrent(
            enabled: true,
            applyScope: scope,
            anchorKey: 'a',
            offMediaKeys: const <String>{},
            fgKey: 'a',
          ),
          isTrue,
        );
      }
    });

    test('currentOnly is on only for its anchored media', () {
      expect(
        resolveApplyToCurrent(
          enabled: true,
          applyScope: BgApplyScope.currentOnly,
          anchorKey: 'a',
          offMediaKeys: const <String>{},
          fgKey: 'a',
        ),
        isTrue,
      );
      expect(
        resolveApplyToCurrent(
          enabled: true,
          applyScope: BgApplyScope.currentOnly,
          anchorKey: 'a',
          offMediaKeys: const <String>{},
          fgKey: 'b',
        ),
        isFalse,
      );
    });

    test('an explicitly closed media reads as not applied', () {
      expect(
        resolveApplyToCurrent(
          enabled: true,
          applyScope: BgApplyScope.all,
          anchorKey: null,
          offMediaKeys: const {'a'},
          fgKey: 'a',
        ),
        isFalse,
      );
    });
  });
}
