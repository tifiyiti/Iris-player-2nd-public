import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/media_library/search/data_source/media_search_data_source.dart';
import 'package:iris/features/media_library/search/model/search_result_item.dart';

void main() {
  SearchResultItem db(int i) => SearchResultItem(
        storageId: 's',
        path: 'db$i.mp4',
        name: 'db$i.mp4',
        origin: SearchResultOrigin.dbSource,
      );

  SearchResultItem ex(int i) => SearchResultItem(
        storageId: 's',
        path: 'ex$i.mp4',
        name: 'ex$i.mp4',
        origin: SearchResultOrigin.explicitItem,
      );

  group('SearchVirtualPageMerger (v5-D2 two-segment walk)', () {
    test('total = dbTotal + explicit count', () {
      const m = SearchVirtualPageMerger(dbTotal: 3, explicit: []);
      expect(m.total, 3);
      final m2 = SearchVirtualPageMerger(dbTotal: 0, explicit: [ex(0), ex(1)]);
      expect(m2.total, 2);
    });

    test('explicit block is appended whole after the DB segment', () async {
      final dbItems = [db(0), db(1), db(2)];
      final explicit = [ex(0), ex(1)];
      final m = SearchVirtualPageMerger(dbTotal: 3, explicit: explicit);
      final page = await m.buildPage(0, 100, (i) async => dbItems[i]);
      expect(
        page.map((e) => e.origin).toList(),
        const [
          SearchResultOrigin.dbSource,
          SearchResultOrigin.dbSource,
          SearchResultOrigin.dbSource,
          SearchResultOrigin.explicitItem,
          SearchResultOrigin.explicitItem,
        ],
      );
    });

    test('cross-page walk has no loss and no duplicates (total consistent)',
        () async {
      final dbItems = [db(0), db(1), db(2), db(3)];
      final explicit = [ex(0), ex(1), ex(2)];
      final m = SearchVirtualPageMerger(dbTotal: 4, explicit: explicit);

      final p0 = await m.buildPage(0, 3, (i) async => dbItems[i]);
      final p1 = await m.buildPage(1, 3, (i) async => dbItems[i]);
      final p2 = await m.buildPage(2, 3, (i) async => dbItems[i]);

      final ids = [...p0, ...p1, ...p2].map((e) => e.id).toList();
      expect(ids, [
        's:db0.mp4',
        's:db1.mp4',
        's:db2.mp4',
        's:db3.mp4',
        's:ex0.mp4',
        's:ex1.mp4',
        's:ex2.mp4',
      ]);
      expect(ids.toSet().length, ids.length);
      expect(p0.length + p1.length + p2.length, m.total);
    });

    test('empty explicit segment walks only the DB segment', () async {
      final dbItems = [db(0), db(1)];
      const m = SearchVirtualPageMerger(dbTotal: 2, explicit: []);
      final page = await m.buildPage(0, 10, (i) async => dbItems[i]);
      expect(page.map((e) => e.origin).toList(),
          const [SearchResultOrigin.dbSource, SearchResultOrigin.dbSource]);
    });

    test('out-of-range page returns fewer items, never crashes', () async {
      final dbItems = [db(0)];
      const m = SearchVirtualPageMerger(dbTotal: 1, explicit: []);
      final page = await m.buildPage(9, 10, (i) async => dbItems[i]);
      expect(page, isEmpty);
    });
  });
}
