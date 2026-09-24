import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/model/enum/bg_source_rule_kind.dart';
import 'package:iris/features/background_playback/model/source/bg_source_rule.dart';
import 'package:iris/features/background_playback/services/bg_source_staging.dart';

BgSourceRule _rule({
  required String id,
  bool enabled = true,
  bool pinned = false,
  bool builtin = false,
  int sortOrder = 0,
  String name = '',
}) =>
    BgSourceRule(
      id: id,
      name: name,
      enabled: enabled,
      pinned: pinned,
      builtin: builtin,
      sortOrder: sortOrder,
    );

void main() {
  group('diffBgSourceRules', () {
    test('a no-op staging yields an empty diff', () {
      final original = [_rule(id: 'a'), _rule(id: 'b', sortOrder: 1)];
      final diff = diffBgSourceRules(original: original, working: original);
      expect(diff.isEmpty, isTrue);
      expect(diff.toSave, isEmpty);
      expect(diff.toDelete, isEmpty);
    });

    test('an enabled/pin flip is a save, not a delete', () {
      final original = [_rule(id: 'a')];
      final working = [_rule(id: 'a', enabled: false, pinned: true)];
      final diff = diffBgSourceRules(original: original, working: working);
      expect(diff.toSave.map((r) => r.id), ['a']);
      expect(diff.toSave.single.enabled, isFalse);
      expect(diff.toSave.single.pinned, isTrue);
      expect(diff.toDelete, isEmpty);
    });

    test('an added rule is saved, a removed rule is deleted', () {
      final original = [_rule(id: 'a'), _rule(id: 'b', sortOrder: 1)];
      final working = [_rule(id: 'a'), _rule(id: 'c', sortOrder: 2)];
      final diff = diffBgSourceRules(original: original, working: working);
      expect(diff.toSave.map((r) => r.id), ['c']);
      expect(diff.toDelete, ['b']);
    });

    test('the built-in rule is never scheduled for deletion', () {
      final original = [
        _rule(id: 'builtin', builtin: true),
        _rule(id: 'b', sortOrder: 1),
      ];
      final diff = diffBgSourceRules(original: original, working: const []);
      expect(diff.toDelete, ['b']);
    });

    test('an edited field (not just enable/pin) is a save', () {
      final original = [_rule(id: 'a', name: 'old')];
      final working = [_rule(id: 'a', name: 'new')];
      final diff = diffBgSourceRules(original: original, working: working);
      expect(diff.toSave.single.name, 'new');
    });
  });

  group('sortStagedRules', () {
    test('orders pinned-first, then sortOrder, then id', () {
      final rules = [
        _rule(id: 'a', sortOrder: 0),
        _rule(id: 'b', sortOrder: 1),
        _rule(id: 'c', sortOrder: 5, pinned: true),
        _rule(id: 'd', sortOrder: 5),
      ];
      expect(
        sortStagedRules(rules).map((r) => r.id).toList(),
        ['c', 'a', 'b', 'd'],
      );
    });
  });

  group('nextStagedSortOrder', () {
    test('starts at 0 and appends after the maximum', () {
      expect(nextStagedSortOrder(const []), 0);
      expect(
        nextStagedSortOrder([
          _rule(id: 'a', sortOrder: 0),
          _rule(id: 'b', sortOrder: 3),
        ]),
        4,
      );
    });
  });

  test('BgSourceRuleKind still round-trips through copyWith', () {
    final r = _rule(id: 'a');
    expect(r.copyWith(kind: BgSourceRuleKind.directory).kind,
        BgSourceRuleKind.directory);
  });
}
