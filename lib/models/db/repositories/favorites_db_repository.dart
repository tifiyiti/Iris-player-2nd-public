import 'dart:convert';

import 'package:iris/models/db/adapters/favorite_drift_adapter.dart';
import 'package:iris/models/db/dao/favorites_dao.dart';
import 'package:iris/models/store/storage_state.dart';

class FavoritesDbRepository {
  final FavoritesDao dao;
  FavoritesDbRepository(this.dao);

  Future<List<Favorite>> getFavorites() async {
    final rows = await dao.getAll();
    return rows.map(FavoriteDriftAdapter.fromDb).toList();
  }

  Future<void> addFavorite(Favorite favorite) {
    return dao.upsert(favorite.toCompanion());
  }

  Future<void> removeFavorite(Favorite favorite) {
    return dao.deleteByKey(
      favorite.storageId,
      json.encode(favorite.path),
    );
  }

  Future<void> replaceAllFavorites(List<Favorite> favorites) {
    return dao.replaceAll(
      favorites.map((f) => f.toCompanion()).toList(),
    );
  }
}
