import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/model/enum/basic_enum.dart';
import 'package:iris/features/scenario_playback/model/enum/scenario_manage_sort_by.dart';
import 'package:iris/features/scenario_playback/store/playback_scenario_store_state.dart';
import 'package:iris/features/scenario_playback/store/use_playback_scenario_store.dart';
import 'package:iris/features/scenario_playback/view/sources/paged_scenario_sources_data_source.dart';

/// Store subclass that never touches secure storage / the DB so the manage
/// sort methods can be unit-tested in isolation.
class _TestPlaybackScenarioStore extends PlaybackScenarioStore {
  @override
  Future<PlaybackScenarioStoreState?> load() async => null;

  @override
  Future<void> save(PlaybackScenarioStoreState s) async {}

  @override
  void onReady() {}
}

const _defaultGroupOrder = [
  ScenarioManageGroup.dirSources,
  ScenarioManageGroup.itemSources,
  ScenarioManageGroup.dirExclude,
  ScenarioManageGroup.itemExclude,
];

ScenarioManageItem _item({
  ScenarioManageItemKind kind = ScenarioManageItemKind.source,
  int id = 1,
  String sortName = '',
  String containerKey = '',
  String storageName = '',
  DateTime? createdAt,
  String? storageId = 's1',
  String? path,
  bool isFile = false,
}) {
  return ScenarioManageItem(
    kind: kind,
    group: switch (kind) {
      ScenarioManageItemKind.source =>
        isFile ? ScenarioManageGroup.itemSources : ScenarioManageGroup.dirSources,
      ScenarioManageItemKind.exclude =>
        isFile ? ScenarioManageGroup.itemExclude : ScenarioManageGroup.dirExclude,
      ScenarioManageItemKind.include => ScenarioManageGroup.itemSources,
    },
    sourceId: kind == ScenarioManageItemKind.source ? id : null,
    ruleId: kind == ScenarioManageItemKind.exclude ? id : null,
    includeId: kind == ScenarioManageItemKind.include ? id : null,
    title: sortName,
    subtitle: sortName,
    sortName: sortName,
    containerKey: containerKey,
    storageName: storageName,
    createdAt: createdAt,
    storageId: storageId,
    path: path,
    isFile: isFile,
  );
}

List<ScenarioManageItem> _sorted(
  List<ScenarioManageItem> items, {
  List<ScenarioManageGroup> groupOrder = _defaultGroupOrder,
  ScenarioManageSortBy sortBy = ScenarioManageSortBy.name,
  SortDirection direction = SortDirection.asc,
  bool withinGroup = true,
  bool containerFirst = false,
}) {
  final list = [...items];
  list.sort((a, b) => compareManageItems(
        a,
        b,
        groupOrder: groupOrder,
        sortBy: sortBy,
        direction: direction,
        withinGroup: withinGroup,
        containerFirst: containerFirst,
      ));
  return list;
}

List<String> _names(List<ScenarioManageItem> items) =>
    items.map((e) => e.sortName).toList();

void main() {
  group('PlaybackScenarioStore manage sort', () {
    test('defaults: name + asc + withinGroup', () {
      final store = _TestPlaybackScenarioStore();
      expect(store.state.manageSortBy, ScenarioManageSortBy.name);
      expect(store.state.manageSortDirection, SortDirection.asc);
      expect(store.state.manageSortWithinGroup, isTrue);
    });

    test('setManageSort updates field + direction', () async {
      final store = _TestPlaybackScenarioStore();
      await store.setManageSort(ScenarioManageSortBy.type, SortDirection.desc);
      expect(store.state.manageSortBy, ScenarioManageSortBy.type);
      expect(store.state.manageSortDirection, SortDirection.desc);
    });

    test('setManageSortWithinGroup toggles', () async {
      final store = _TestPlaybackScenarioStore();
      await store.setManageSortWithinGroup(false);
      expect(store.state.manageSortWithinGroup, isFalse);
    });
  });

  group('compareManageItems', () {
    test('Name: case-insensitive basename, asc/desc', () {
      final items = [
        _item(sortName: 'banana', id: 1),
        _item(sortName: 'Apple', id: 2),
        _item(sortName: 'cherry', id: 3),
      ];
      expect(_names(_sorted(items)), ['Apple', 'banana', 'cherry']);
      expect(_names(_sorted(items, direction: SortDirection.desc)),
          ['cherry', 'banana', 'Apple']);
    });

    test('Type within itemSources group: source < include', () {
      final items = [
        _item(kind: ScenarioManageItemKind.include, isFile: true, sortName: 'b.mp4', id: 1),
        _item(kind: ScenarioManageItemKind.source, isFile: true, sortName: 'a.mp4', id: 2),
      ];
      final sorted = _sorted(items, sortBy: ScenarioManageSortBy.type);
      expect(sorted.map((e) => e.kind).toList(),
          [ScenarioManageItemKind.source, ScenarioManageItemKind.include]);
    });

    test('Type global (withinGroup off): all sources -> includes -> excludes', () {
      final items = [
        _item(kind: ScenarioManageItemKind.exclude, isFile: false, sortName: 'x', id: 1),
        _item(kind: ScenarioManageItemKind.source, isFile: true, sortName: 'y', id: 2),
        _item(kind: ScenarioManageItemKind.include, isFile: true, sortName: 'z', id: 3),
        _item(kind: ScenarioManageItemKind.source, isFile: false, sortName: 'w', id: 4),
      ];
      final sorted = _sorted(items, sortBy: ScenarioManageSortBy.type, withinGroup: false);
      expect(sorted.map((e) => e.kind).toList(), [
        ScenarioManageItemKind.source,
        ScenarioManageItemKind.source,
        ScenarioManageItemKind.include,
        ScenarioManageItemKind.exclude,
      ]);
    });

    test('Storage: case-insensitive storage name', () {
      final items = [
        _item(storageName: 'Beta', sortName: 'a', id: 1),
        _item(storageName: 'alpha', sortName: 'b', id: 2),
      ];
      expect(_names(_sorted(items, sortBy: ScenarioManageSortBy.storage)), ['b', 'a']);
    });

    test('Path: storageId prefix, root first, case-insensitive', () {
      final items = [
        _item(sortName: 'Z.mp4', path: 'dir/Z.mp4', id: 1),
        _item(sortName: 'a.mp4', path: 'dir/a.mp4', id: 2),
        _item(sortName: 'root', path: null, id: 3),
      ];
      expect(_names(_sorted(items, sortBy: ScenarioManageSortBy.path)),
          ['root', 'a.mp4', 'Z.mp4']);
    });

    test('Created: null sorts as epoch 0 (asc first, desc last)', () {
      final items = [
        _item(sortName: 'hasDate', createdAt: DateTime(2026), id: 1),
        _item(sortName: 'nullDate', createdAt: null, id: 2),
      ];
      expect(_names(_sorted(items, sortBy: ScenarioManageSortBy.createdAt)),
          ['nullDate', 'hasDate']);
      expect(
          _names(_sorted(items,
              sortBy: ScenarioManageSortBy.createdAt,
              direction: SortDirection.desc)),
          ['hasDate', 'nullDate']);
    });

    test('withinGroup: custom groupOrder is the primary key', () {
      final items = [
        _item(kind: ScenarioManageItemKind.exclude, isFile: false, sortName: 'aaa', id: 1),
        _item(sortName: 'zzz', id: 2),
      ];
      const order = [
        ScenarioManageGroup.dirExclude,
        ScenarioManageGroup.dirSources,
        ScenarioManageGroup.itemSources,
        ScenarioManageGroup.itemExclude,
      ];
      final sorted = _sorted(items, groupOrder: order);
      expect(sorted.map((e) => e.kind).toList(),
          [ScenarioManageItemKind.exclude, ScenarioManageItemKind.source]);
    });

    test('withinGroup off: group order ignored, field sorts globally', () {
      final items = [
        _item(kind: ScenarioManageItemKind.exclude, isFile: false, sortName: 'a', id: 1),
        _item(sortName: 'b', id: 2),
      ];
      final sorted = _sorted(items, withinGroup: false);
      expect(_names(sorted), ['a', 'b']);
    });

    test('containerFirst: direction applies to container keys', () {
      final items = [
        _item(sortName: 'b', containerKey: 's1:/z', id: 1),
        _item(sortName: 'a', containerKey: 's1:/a', id: 2),
      ];
      final asc = _sorted(items, containerFirst: true);
      expect(asc.map((e) => e.containerKey).toList(), ['s1:/a', 's1:/z']);
      final desc =
          _sorted(items, containerFirst: true, direction: SortDirection.desc);
      expect(desc.map((e) => e.containerKey).toList(), ['s1:/z', 's1:/a']);
    });

    test('container tie-break is direction-neutral (desc stays stable)', () {
      final items = [
        _item(sortName: 'same', containerKey: 's1:/b', id: 1),
        _item(sortName: 'same', containerKey: 's1:/a', id: 2),
        _item(sortName: 'same', containerKey: 's1:/c', id: 3),
      ];
      final asc = _sorted(items);
      final desc = _sorted(items, direction: SortDirection.desc);
      // Field keys tie, so container tie-break (direction-neutral) keeps the
      // forward order; desc only reverses the field key, which is equal here.
      expect(asc.map((e) => e.containerKey).toList(),
          ['s1:/a', 's1:/b', 's1:/c']);
      expect(desc.map((e) => e.containerKey).toList(),
          ['s1:/a', 's1:/b', 's1:/c']);
    });

    test('comparator is a total order (antisymmetric, reflexive, transitive)',
        () {
      final items = [
        _item(sortName: 'a', storageName: 'Z', containerKey: 's1:/z',
            createdAt: DateTime(2024), id: 5, path: 'x/a.mp4'),
        _item(sortName: 'B', storageName: 'a', containerKey: 's1:/a',
            createdAt: null, id: 3, path: 'b/B.mp4'),
        _item(kind: ScenarioManageItemKind.include, isFile: true, sortName: 'c',
            storageName: 'M', containerKey: 's2:/q', createdAt: DateTime(2026),
            id: 1, path: 'q/c.mp4'),
        _item(kind: ScenarioManageItemKind.exclude, isFile: false, sortName: 'd',
            storageName: 'm', containerKey: 's2:/p', createdAt: DateTime(2025),
            id: 9, path: 'p/d'),
      ];

      for (final sortBy in ScenarioManageSortBy.values) {
        for (final direction in SortDirection.values) {
          for (final withinGroup in [true, false]) {
            for (final containerFirst in [true, false]) {
              int cmp(ScenarioManageItem a, ScenarioManageItem b) =>
                  compareManageItems(
                    a,
                    b,
                    groupOrder: _defaultGroupOrder,
                    sortBy: sortBy,
                    direction: direction,
                    withinGroup: withinGroup,
                    containerFirst: containerFirst,
                  );
              final reason =
                  'sortBy=$sortBy dir=$direction within=$withinGroup container=$containerFirst';

              for (final a in items) {
                expect(cmp(a, a), 0, reason: 'reflexivity $reason');
                for (final b in items) {
                  expect(cmp(a, b), -cmp(b, a), reason: 'antisymmetry $reason');
                  for (final c in items) {
                    if (cmp(a, b) <= 0 && cmp(b, c) <= 0) {
                      expect(cmp(a, c) <= 0, isTrue,
                          reason: 'transitivity $reason');
                    }
                  }
                }
              }
            }
          }
        }
      }
    });
  });
}
