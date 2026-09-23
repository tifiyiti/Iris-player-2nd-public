import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/meta_settings/data/value_codec.dart';
import 'package:iris/features/meta_settings/model/enum/setting_value_type.dart';

void main() {
  group('ValueCodec encode/decode roundtrip', () {
    test('bool', () {
      expect(ValueCodec.encode(SettingValueType.bool, true), '1');
      expect(ValueCodec.encode(SettingValueType.bool, false), '0');
      expect(ValueCodec.decodeBool('1'), isTrue);
      expect(ValueCodec.decodeBool('0'), isFalse);
    });

    test('int', () {
      expect(ValueCodec.encode(SettingValueType.int, 42), '42');
      expect(ValueCodec.decodeInt('42'), 42);
      expect(ValueCodec.decodeInt('-7'), -7);
    });

    test('double', () {
      expect(
        ValueCodec.encode(SettingValueType.double, 0.5),
        0.5.toString(),
      );
      expect(ValueCodec.decodeDouble('0.5'), 0.5);
      expect(ValueCodec.decodeDouble('2'), 2.0); // int-form tolerated
    });

    test('string', () {
      expect(ValueCodec.encode(SettingValueType.string, 'zh'), 'zh');
      expect(ValueCodec.decodeString('zh-CN'), 'zh-CN');
      expect(ValueCodec.decodeString(null), isNull);
    });

    test('enumeration stores the value NAME verbatim', () {
      expect(ValueCodec.encode(SettingValueType.enumeration, 'mediaKit'),
          'mediaKit');
      expect(ValueCodec.decodeString('mediaKit'), 'mediaKit');
    });

    test('json', () {
      final payload = <String, dynamic>{'a': 1, 'b': ['x', 'y']};
      final encoded = ValueCodec.encode(SettingValueType.json, payload);
      expect(jsonDecode(encoded!), payload);
      expect(ValueCodec.decodeJson(encoded), payload);
    });
  });

  group('ValueCodec error containment (never throws at read time)', () {
    test('encode type mismatch returns null', () {
      expect(ValueCodec.encode(SettingValueType.bool, 'yes'), isNull);
      expect(ValueCodec.encode(SettingValueType.int, 1.5), isNull);
      expect(ValueCodec.encode(SettingValueType.enumeration, 3), isNull);
    });

    test('decode malformed falls back', () {
      expect(ValueCodec.decodeBool('true'), isFalse); // wrong literal
      expect(ValueCodec.decodeBool(null), isFalse);
      expect(ValueCodec.decodeInt('abc'), 0);
      expect(ValueCodec.decodeInt('', fallback: 9), 9);
      expect(ValueCodec.decodeDouble('NaN!'), 0.0);
      expect(ValueCodec.decodeDouble('oops', fallback: 1.25), 1.25);
    });

    test('decodeStringList tolerates garbage and non-string entries', () {
      expect(ValueCodec.decodeStringList('["a","b"]'), ['a', 'b']);
      expect(ValueCodec.decodeStringList('{broken'), isEmpty);
      expect(ValueCodec.decodeStringList('[1,"a"]'), ['a']);
      expect(ValueCodec.decodeStringList(null), isEmpty);
    });

    test('decodeJson tolerates broken payload', () {
      expect(ValueCodec.decodeJson('{broken'), isNull);
      expect(ValueCodec.decodeJson(null), isNull);
    });

    test('null encodes to null for every family', () {
      for (final t in SettingValueType.values) {
        expect(ValueCodec.encode(t, null), isNull);
      }
    });
  });
}
