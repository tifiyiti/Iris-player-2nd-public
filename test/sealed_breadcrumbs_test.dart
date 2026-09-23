import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/paginated_browser/utils/breadcrumbs.dart';

void main() {
  group('sealedPathBreadcrumbs', () {
    test('multi-segment base seals to name plus relative tail', () {
      final crumbs = sealedPathBreadcrumbs(
        sealedName: 'Movies',
        path: const ['storage', 'emulated', '0', 'Movies', 'sub'],
        basePath: const ['storage', 'emulated', '0', 'Movies'],
      );
      expect(crumbs, <String>['Movies', 'sub']);
    });

    test('at sealed root shows only the sealed name', () {
      final crumbs = sealedPathBreadcrumbs(
        sealedName: 'Movies',
        path: const ['storage', 'emulated', '0', 'Movies'],
        basePath: const ['storage', 'emulated', '0', 'Movies'],
      );
      expect(crumbs, <String>['Movies']);
    });

    test('never leaks base segments above the sealed root', () {
      final crumbs = sealedPathBreadcrumbs(
        sealedName: '内部存储',
        path: const ['storage', 'emulated', '0'],
        basePath: const ['storage', 'emulated', '0'],
      );
      expect(crumbs, <String>['内部存储']);
      expect(crumbs, isNot(contains('emulated')));
      expect(crumbs, isNot(contains('storage')));
    });
  });

  group('sealedCrumbTarget', () {
    test('multi-segment base maps crumb index to absolute length', () {
      expect(sealedCrumbTarget(baseLength: 4, crumbIndex: 0), 4);
      expect(sealedCrumbTarget(baseLength: 4, crumbIndex: 1), 5);
      expect(sealedCrumbTarget(baseLength: 1, crumbIndex: 2), 3);
    });
  });

  group('contentBreadcrumbs sealed fallback', () {
    test('prefix mismatch never leaks the absolute parent path', () {
      final crumbs = contentBreadcrumbs(
        storageName: 'MyLib',
        parentPath: '/storage/emulated/0/Movies/sub',
        sourceRoot: '/other/root',
      );
      expect(crumbs.first, 'Sources');
      expect(crumbs, isNot(contains('emulated')));
      expect(crumbs, isNot(contains('storage')));
    });

    test('matching prefix keeps sealed root plus relative tail', () {
      final crumbs = contentBreadcrumbs(
        storageName: 'MyLib',
        parentPath: '/base/Movies/sub',
        sourceRoot: '/base/Movies',
      );
      expect(crumbs, <String>['Sources', 'MyLib', 'sub']);
    });
  });
}
