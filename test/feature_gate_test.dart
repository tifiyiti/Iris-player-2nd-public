import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/meta_settings/contributions/feature_flags_contribution.dart';
import 'package:iris/features/meta_settings/data/feature_gate.dart';
import 'package:iris/features/meta_settings/model/enum/feature_stage.dart';
import 'package:iris/features/meta_settings/model/feature_flag.dart';

FeatureFlag _flag(
  FeatureStage stage, {
  bool defaultEnabled = false,
  bool? userOverride,
}) =>
    FeatureFlag(
      key: 'f',
      stage: stage,
      defaultEnabled: defaultEnabled,
      userOverride: userOverride,
    );

void main() {
  group('FeatureGate truth table', () {
    test('unknown flag resolves OFF regardless of platform', () {
      expect(FeatureGate.resolve(null, platformSupported: true), isFalse);
      expect(FeatureGate.resolve(null, platformSupported: false), isFalse);
    });

    test('platform unsupported always wins (compile-time gate)', () {
      expect(
        FeatureGate.resolve(
          _flag(FeatureStage.ga, defaultEnabled: true),
          platformSupported: false,
        ),
        isFalse,
      );
      expect(
        FeatureGate.resolve(
          _flag(FeatureStage.ga, userOverride: true),
          platformSupported: false,
        ),
        isFalse,
      );
    });

    test('retired forces OFF even with explicit override', () {
      expect(
        FeatureGate.resolve(
          _flag(FeatureStage.retired, userOverride: true, defaultEnabled: true),
          platformSupported: true,
        ),
        isFalse,
      );
    });

    test('alpha/beta/ga follow default when no override', () {
      expect(
        FeatureGate.resolve(_flag(FeatureStage.alpha), platformSupported: true),
        isFalse,
      );
      expect(
        FeatureGate.resolve(
          _flag(FeatureStage.beta, defaultEnabled: true),
          platformSupported: true,
        ),
        isTrue,
      );
      expect(
        FeatureGate.resolve(
          _flag(FeatureStage.ga, defaultEnabled: true),
          platformSupported: true,
        ),
        isTrue,
      );
    });

    test('explicit override beats default', () {
      expect(
        FeatureGate.resolve(
          _flag(FeatureStage.alpha, userOverride: true), // opt-in to alpha
          platformSupported: true,
        ),
        isTrue,
      );
      expect(
        FeatureGate.resolve(
          _flag(FeatureStage.ga, defaultEnabled: true, userOverride: false),
          platformSupported: true,
        ),
        isFalse,
      );
    });
  });

  group('FeatureFlagsContribution invariants', () {
    test('seed keys are unique and stages valid', () {
      final keys = FeatureFlagsContribution.flags.map((f) => f.key).toList();
      expect(keys.toSet().length, keys.length);
      for (final f in FeatureFlagsContribution.flags) {
        expect(FeatureStage.values, contains(f.stage));
      }
    });
  });
}
