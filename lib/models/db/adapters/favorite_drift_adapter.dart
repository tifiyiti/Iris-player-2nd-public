import 'dart:convert';

import 'package:iris/models/db/app_database.dart';
import 'package:iris/models/store/storage_state.dart';

extension FavoriteDriftAdapter on Favorite {
  static Favorite fromDb(FavoritesTableData row) {
    return Favorite(
      storageId: row.storageId,
      path: List<String>.from(json.decode(row.path)),
    );
  }

  FavoritesTableCompanion toCompanion() {
    return FavoritesTableCompanion.insert(
      storageId: storageId,
      path: json.encode(path),
    );
  }
}
