import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/enum/media_lib_sources.dart';
import 'package:iris/features/media_library/search/model/search_context.dart';
import 'package:iris/features/media_library/search/model/search_exclude_rule.dart';
import 'package:iris/features/media_library/search/model/search_path_match.dart';
import 'package:iris/features/scenario_playback/model/enum/exclude_rule_kind.dart';
import 'package:iris/features/scenario_playback/model/enum/exclude_scope.dart';

void main() {
  group('sourceCovers (scope-in semantics, §5.1.2)', () {
    test('directory + recursive covers exact-or-prefix (with itself)', () {
      const src = SearchSource(
        storageId: 's',
        path: 'a',
        kind: MediaSourceKind.directory,
        recursive: true,
      );
      expect(sourceCovers(src, 's', 'a/b/c.mp4'), isTrue);
      expect(sourceCovers(src, 's', 'a'), isTrue);
      expect(sourceCovers(src, 's', 'ab/x.mp4'), isFalse);
      expect(sourceCovers(src, 's', 'b/x.mp4'), isFalse);
      expect(sourceCovers(src, 'other', 'a/x.mp4'), isFalse);
    });

    test('directory + non-recursive covers direct children only', () {
      const src = SearchSource(
        storageId: 's',
        path: 'a',
        kind: MediaSourceKind.directory,
        recursive: false,
      );
      expect(sourceCovers(src, 's', 'a/b.mp4'), isTrue);
      expect(sourceCovers(src, 's', 'a/b/c.mp4'), isFalse);
      expect(sourceCovers(src, 's', 'a'), isFalse);
    });

    test('directory + non-recursive at storage root = parentPath null (v5-D5)',
        () {
      const src = SearchSource(
        storageId: 's',
        path: '',
        kind: MediaSourceKind.directory,
        recursive: false,
      );
      expect(sourceCovers(src, 's', 'b.mp4'), isTrue);
      expect(sourceCovers(src, 's', 'a/b.mp4'), isFalse);
    });

    test('storage source covers the whole storage', () {
      const src = SearchSource(storageId: 's', kind: MediaSourceKind.storage);
      expect(sourceCovers(src, 's', 'deep/nested/x.mp4'), isTrue);
      expect(sourceCovers(src, 'other', 'x.mp4'), isFalse);
    });

    test('file source covers exact path only', () {
      const src = SearchSource(
        storageId: 's',
        path: 'a/b.mp4',
        kind: MediaSourceKind.file,
      );
      expect(sourceCovers(src, 's', 'a/b.mp4'), isTrue);
      expect(sourceCovers(src, 's', 'a/c.mp4'), isFalse);
    });

    test('anySourceCovers ORs across sources', () {
      const srcs = [
        SearchSource(storageId: 's', path: 'a', kind: MediaSourceKind.directory,
            recursive: true),
        SearchSource(storageId: 's', path: 'b', kind: MediaSourceKind.directory,
            recursive: false),
      ];
      expect(anySourceCovers(srcs, 's', 'a/x.mp4'), isTrue);
      expect(anySourceCovers(srcs, 's', 'b/x.mp4'), isTrue);
      expect(anySourceCovers(srcs, 's', 'b/x/y.mp4'), isFalse);
      expect(anySourceCovers(srcs, 'z', 'a/x.mp4'), isFalse);
    });
  });

  group('explicitExcludedByScenarioRules (v5-D3, scenario-scoped only)', () {
    SearchExcludeRule dirRule(String path, {bool recursive = true}) =>
        SearchExcludeRule(
          scope: ExcludeScope.scenario,
          kind: ExcludeRuleKind.directory,
          storageId: 's',
          path: path,
          recursive: recursive,
        );

    SearchExcludeRule mediaRule(String path) => SearchExcludeRule(
          scope: ExcludeScope.scenario,
          kind: ExcludeRuleKind.media,
          storageId: 's',
          path: path,
        );

    test('directory recursive prunes the whole subtree', () {
      expect(explicitExcludedByScenarioRules([dirRule('a')], 's', 'a/b.mp4'),
          isTrue);
      expect(
          explicitExcludedByScenarioRules([dirRule('a')], 's', 'a/b/c.mp4'),
          isTrue);
      expect(explicitExcludedByScenarioRules([dirRule('a')], 's', 'x.mp4'),
          isFalse);
    });

    test('directory non-recursive prunes direct children only', () {
      final r = dirRule('a', recursive: false);
      expect(explicitExcludedByScenarioRules([r], 's', 'a/b.mp4'), isTrue);
      expect(explicitExcludedByScenarioRules([r], 's', 'a/b/c.mp4'), isFalse);
    });

    test('storage-root directory exclude prunes everything in that storage', () {
      expect(explicitExcludedByScenarioRules([dirRule('')], 's', 'a/b.mp4'),
          isTrue);
      expect(explicitExcludedByScenarioRules([dirRule('')], 'other', 'a.mp4'),
          isFalse);
    });

    test('media rule prunes the exact path', () {
      expect(
          explicitExcludedByScenarioRules([mediaRule('a/b.mp4')], 's', 'a/b.mp4'),
          isTrue);
      expect(
          explicitExcludedByScenarioRules([mediaRule('a/b.mp4')], 's', 'a/c.mp4'),
          isFalse);
    });

    test('source-scoped rules never prune explicit items (v5-D3)', () {
      final sourceRule = SearchExcludeRule(
        scope: ExcludeScope.source,
        sourceId: 7,
        kind: ExcludeRuleKind.directory,
        storageId: 's',
        path: 'a',
        recursive: true,
      );
      expect(explicitExcludedByScenarioRules([sourceRule], 's', 'a/b.mp4'),
          isFalse);
    });
  });
}
