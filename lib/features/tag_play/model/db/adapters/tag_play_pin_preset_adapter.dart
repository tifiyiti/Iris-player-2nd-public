import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:iris/features/tag_play/model/domain/tag_play_pin_preset.dart';
import 'package:iris/models/db/app_database.dart';

extension TagPlayPinPresetAdapter on TagPlayPinPreset {
  static TagPlayPinPreset fromDb(VideoTagPinPresetsTableData row) {
    List<int> ids = const [];
    try {
      final decoded = json.decode(row.pinnedTagIds);
      if (decoded is List) {
        ids = decoded.whereType<int>().toList(growable: false);
      }
    } catch (_) {
      // Malformed payload degrades to an empty preset instead of throwing.
    }
    return TagPlayPinPreset(
      id: row.id,
      name: row.name,
      pinnedTagIds: ids,
      createdAt: row.createdAt,
    );
  }

  VideoTagPinPresetsTableCompanion toCompanion() {
    return VideoTagPinPresetsTableCompanion(
      id: id == 0 ? const Value.absent() : Value(id),
      name: Value(name),
      pinnedTagIds: Value(json.encode(pinnedTagIds)),
      createdAt:
          createdAt == null ? const Value.absent() : Value(createdAt!),
    );
  }
}
