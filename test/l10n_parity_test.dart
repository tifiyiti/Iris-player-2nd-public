import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ARB parity: en is the template and the fallback for everything.
/// zh must cover every en key; placeholders must match so runtime
/// interpolation never breaks. If this fails, fix the ARB, not the test.
void main() {
  Map<String, dynamic> loadArb(String name) {
    final file = File('lib/l10n/$name');
    expect(file.existsSync(), isTrue, reason: 'missing $name');
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }

  Set<String> keys(Map<String, dynamic> arb) => arb.keys
      .where((k) => !k.startsWith('@'))
      .toSet();

  bool sameSet(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  Set<String> placeholders(String value) => RegExp(r'\{(\w+)\}')
      .allMatches(value)
      .map((m) => m.group(1)!)
      .toSet();

  group('arb parity en/zh', () {
    test('zh covers every en key (missing keys silently fall back to en)', () {
      final en = loadArb('app_en.arb');
      final zh = loadArb('app_zh.arb');
      final enKeys = keys(en);
      final zhKeys = keys(zh);
      final missing = enKeys.difference(zhKeys);
      expect(missing, isEmpty, reason: 'zh missing: ${missing.join(', ')}');
    });

    test('no NEW camelCase keys (legacy confirmUpdate/releasePage frozen)', () {
      final en = loadArb('app_en.arb');
      const frozen = {'confirmUpdate', 'releasePage'};
      final bad = keys(en)
          .where((k) => !frozen.contains(k) && RegExp(r'[A-Z]').hasMatch(k))
          .toList();
      expect(bad, isEmpty, reason: 'camelCase keys: ${bad.join(', ')}');
    });

    test('placeholders match between en and zh', () {
      final en = loadArb('app_en.arb');
      final zh = loadArb('app_zh.arb');
      final mismatched = <String>[];
      for (final key in keys(en)) {
        final enValue = en[key];
        final zhValue = zh[key];
        if (enValue is! String || zhValue is! String) continue;
        if (!sameSet(placeholders(enValue), placeholders(zhValue))) {
          mismatched.add(key);
        }
      }
      expect(mismatched, isEmpty,
          reason: 'placeholder mismatch: ${mismatched.join(', ')}');
    });

    test('no empty values', () {
      for (final name in ['app_en.arb', 'app_zh.arb']) {
        final arb = loadArb(name);
        final empty = keys(arb)
            .where((k) => (arb[k] as String).trim().isEmpty)
            .toList();
        expect(empty, isEmpty, reason: '$name empty: ${empty.join(', ')}');
      }
    });
  });
}
