import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:flutter/foundation.dart';
import 'package:iris/models/storages/storage.dart';

part 'storage_state.freezed.dart';
part 'storage_state.g.dart';

@freezed
abstract class Favorite with _$Favorite {
  factory Favorite({
    required String storageId,
    required List<String> path,
  }) = _Favorite;

  factory Favorite.fromJson(Map<String, dynamic> json) =>
      _$FavoriteFromJson(json);
}

@freezed
abstract class StorageState with _$StorageState {
  factory StorageState({
    @Default([]) List<Storage> storages,
    @Default([]) List<Favorite> favorites,
    @Default(null) Storage? currentStorage,
    @Default([]) List<String> currentPath,
    @JsonKey(
      includeFromJson: false,
      includeToJson: false,
    )
    @Default({})
    Map<String, bool> storageConnectionStatus,
  }) = _StorageState;

  factory StorageState.fromJson(Map<String, dynamic> json) =>
      _$StorageStateFromJson(json);
}
