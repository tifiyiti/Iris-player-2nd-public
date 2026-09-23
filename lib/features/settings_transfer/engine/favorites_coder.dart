import 'package:iris/features/settings_transfer/engine/section_coder.dart';
import 'package:iris/features/settings_transfer/model/import_resolution.dart';
import 'package:iris/features/settings_transfer/model/transfer_item_result.dart';
import 'package:iris/models/store/storage_state.dart';
import 'package:iris/store/use_storage_store.dart';

class FavoritesCoder implements SectionCoder {
  @override
  String get sectionKey => 'favorites';

  @override
  Future<Map<String, dynamic>?> encode() async {
    final favs = useStorageStore().state.favorites;
    return {
      'subVersion': 1,
      'payload': favs.map((f) => f.toJson()).toList(),
    };
  }

  @override
  Future<List<TransferItemResult>> importSection(
    Map<String, dynamic>? payload, {
    required TransferResolution resolution,
    required bool skipErrors,
  }) async {
    if (resolution == TransferResolution.skip || payload == null) return [];
    final list = (payload['payload'] as List?) ?? [];
    final results = <TransferItemResult>[];
    try {
      final store = useStorageStore();
      if (resolution == TransferResolution.overwrite) {
        final imported = <Favorite>[];
        for (final raw in list) {
          try {
            imported.add(Favorite.fromJson((raw as Map).cast<String, dynamic>()));
            results.add(TransferItemResult(section: sectionKey, label: raw.toString(), ok: true));
          } catch (e) {
            results.add(TransferItemResult(section: sectionKey, label: raw.toString(), ok: false, error: e.toString()));
            if (!skipErrors) return results;
          }
        }
        // Replace
        final cur = store.state;
        final next = cur.copyWith(favorites: imported);
        // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
        store.set(next);
        await store.save(next);
      } else {
        // append
        for (final raw in list) {
          try {
            final fav = Favorite.fromJson((raw as Map).cast<String, dynamic>());
            // dedup by storageId+path
            final exists = store.state.favorites.any((f) => f.storageId == fav.storageId && _pathEq(f.path, fav.path));
            if (exists) {
              results.add(TransferItemResult(section: sectionKey, label: '${fav.storageId}:${fav.path.join('/')}', ok: true));
              continue;
            }
            await store.addFavorite(fav);
            results.add(TransferItemResult(section: sectionKey, label: '${fav.storageId}:${fav.path.join('/')}', ok: true));
          } catch (e) {
            results.add(TransferItemResult(section: sectionKey, label: raw.toString(), ok: false, error: e.toString()));
            if (!skipErrors) return results;
          }
        }
        if (list.isEmpty) {
          results.add(TransferItemResult(section: sectionKey, label: 'favorites: empty', ok: true));
        }
      }
    } catch (e) {
      results.add(TransferItemResult(section: sectionKey, label: 'favorites', ok: false, error: e.toString()));
    }
    return results;
  }

  bool _pathEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) if (a[i] != b[i]) return false;
    return true;
  }
}
