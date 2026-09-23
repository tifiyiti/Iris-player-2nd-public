import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/virtual_media/rule/vm_naming.dart';

void main() {
  group('parseVmSuffix', () {
    test('matches prefix + digits only', () {
      expect(parseVmSuffix('rule5', 'rule'), 5);
      expect(parseVmSuffix('rule001', 'rule'), 1);
      expect(parseVmSuffix('rule', 'rule'), -1);
      expect(parseVmSuffix('ruleX', 'rule'), -1);
      expect(parseVmSuffix('_dirs_as_virtual', 'rule'), -1);
      expect(parseVmSuffix('other3', 'rule'), -1);
    });

    test('empty prefix falls back to rule', () {
      expect(parseVmSuffix('rule7', '  '), 7);
    });
  });

  group('padNumber', () {
    test('raw/pad variants', () {
      expect(padNumber(5, 'raw'), '5');
      expect(padNumber(5, 'pad2'), '05');
      expect(padNumber(5, 'pad3'), '005');
      expect(padNumber(5, 'pad4'), '0005');
      expect(padNumber(123, 'pad2'), '123');
    });
  });

  group('nextVmRuleName', () {
    test('maxPlusOne ignores gaps', () {
      expect(
        nextVmRuleName(
          existing: const ['rule1', 'rule3'],
          prefix: 'rule',
          numberFormat: 'raw',
          strategy: VmNamingStrategy.maxPlusOne,
        ),
        'rule4',
      );
    });

    test('reuseGap fills smallest hole', () {
      expect(
        nextVmRuleName(
          existing: const ['rule1', 'rule3'],
          prefix: 'rule',
          numberFormat: 'raw',
          strategy: VmNamingStrategy.reuseGap,
        ),
        'rule2',
      );
    });

    test('empty library starts at 1', () {
      expect(
        nextVmRuleName(
          existing: const [],
          prefix: 'rule',
          numberFormat: 'raw',
          strategy: VmNamingStrategy.maxPlusOne,
        ),
        'rule1',
      );
    });

    test('custom prefix and padding', () {
      expect(
        nextVmRuleName(
          existing: const ['my3'],
          prefix: 'my',
          numberFormat: 'pad3',
          strategy: VmNamingStrategy.maxPlusOne,
        ),
        'my004',
      );
    });

    test('globalCounter uses hint, never reuses', () {
      expect(
        nextVmRuleName(
          existing: const ['rule1', 'rule2'],
          prefix: 'rule',
          numberFormat: 'raw',
          strategy: VmNamingStrategy.globalCounter,
          counterHint: 10,
        ),
        'rule11',
      );
    });
  });

  group('formatVmTimestamp', () {
    test('local ms format', () {
      final t = DateTime(2026, 9, 5, 14, 23, 45, 123);
      expect(formatVmTimestamp(t), '2026-09-05 14:23:45.123');
    });
  });
}
