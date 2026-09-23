import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/services/source_delete_coverage.dart';

void main() {
  group('resolveSourceDeleteNodeAction', () {
    test('no sibling → the deleted source owns the range', () {
      expect(
        resolveSourceDeleteNodeAction(sourcePath: 'a/b', siblingPaths: const []),
        SourceDeleteNodeAction.deleteRange,
      );
      expect(
        resolveSourceDeleteNodeAction(sourcePath: '', siblingPaths: const []),
        SourceDeleteNodeAction.deleteStorage,
      );
    });

    test('a full-storage sibling covers any range → keep', () {
      expect(
        resolveSourceDeleteNodeAction(
          sourcePath: 'a/b',
          siblingPaths: const [null],
        ),
        SourceDeleteNodeAction.keep,
      );
      expect(
        resolveSourceDeleteNodeAction(
          sourcePath: 'a/b',
          siblingPaths: const [''],
        ),
        SourceDeleteNodeAction.keep,
      );
    });

    test('an ANCESTOR sibling covers the deleted range → keep', () {
      // P0-1 regression: deleting the child /a/b while parent /a survives must
      // NOT drop /a/b's rows.
      expect(
        resolveSourceDeleteNodeAction(
          sourcePath: 'a/b',
          siblingPaths: const ['a'],
        ),
        SourceDeleteNodeAction.keep,
      );
      expect(
        resolveSourceDeleteNodeAction(
          sourcePath: 'a/b/c',
          siblingPaths: const ['a'],
        ),
        SourceDeleteNodeAction.keep,
      );
    });

    test('a DESCENDANT sibling needs a subset → keep', () {
      expect(
        resolveSourceDeleteNodeAction(
          sourcePath: 'a',
          siblingPaths: const ['a/b'],
        ),
        SourceDeleteNodeAction.keep,
      );
    });

    test('an equal sibling covers the range → keep', () {
      expect(
        resolveSourceDeleteNodeAction(
          sourcePath: 'a/b',
          siblingPaths: const ['a/b'],
        ),
        SourceDeleteNodeAction.keep,
      );
    });

    test('only unrelated siblings → drop the range', () {
      expect(
        resolveSourceDeleteNodeAction(
          sourcePath: 'a/b',
          siblingPaths: const ['c/d', 'x'],
        ),
        SourceDeleteNodeAction.deleteRange,
      );
    });

    test('deleting a full-storage source with descendants → keep', () {
      expect(
        resolveSourceDeleteNodeAction(
          sourcePath: '',
          siblingPaths: const ['a/b'],
        ),
        SourceDeleteNodeAction.keep,
      );
    });

    test('leading-slash conventions never hide an overlap', () {
      expect(
        resolveSourceDeleteNodeAction(
          sourcePath: '/a/b',
          siblingPaths: const ['a'],
        ),
        SourceDeleteNodeAction.keep,
      );
      expect(
        resolveSourceDeleteNodeAction(
          sourcePath: 'a/b',
          siblingPaths: const ['/a/b'],
        ),
        SourceDeleteNodeAction.keep,
      );
    });
  });
}
