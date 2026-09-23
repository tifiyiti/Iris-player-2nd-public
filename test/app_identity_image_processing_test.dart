import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/app_identity/services/app_identity_validation.dart';

void main() {
  group('AppIdentityValidation.validateName', () {
    test('empty after trim fails', () {
      expect(AppIdentityValidation.validateName('  '), 'empty');
      expect(AppIdentityValidation.validateName(''), 'empty');
    });

    test('too long fails', () {
      final long = 'a' * (AppIdentityValidation.maxNameLength + 1);
      expect(AppIdentityValidation.validateName(long), 'too_long');
      final ok = 'a' * AppIdentityValidation.maxNameLength;
      expect(AppIdentityValidation.validateName(ok), isNull);
    });

    test('control chars fail', () {
      expect(AppIdentityValidation.validateName('hello\nworld'), 'control_char');
      expect(AppIdentityValidation.validateName('a\u0000b'), 'control_char');
    });

    test('valid names pass', () {
      expect(AppIdentityValidation.validateName('My IRIS'), isNull);
      expect(AppIdentityValidation.validateName('  My IRIS  '), isNull);
      expect(AppIdentityValidation.validateName('IRIS-2_播放'), isNull);
    });

    test('normalizeName trims', () {
      expect(AppIdentityValidation.normalizeName('  hi  '), 'hi');
    });
  });
}
