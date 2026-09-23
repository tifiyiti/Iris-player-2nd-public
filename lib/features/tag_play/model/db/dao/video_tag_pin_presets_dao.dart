import 'package:drift/drift.dart';
import 'package:iris/features/tag_play/model/db/adapters/tag_play_pin_preset_adapter.dart';
import 'package:iris/features/tag_play/model/db/tables/video_tag_pin_presets_table.dart';
import 'package:iris/features/tag_play/model/domain/tag_play_pin_preset.dart';
import 'package:iris/models/db/app_database.dart';

part 'video_tag_pin_presets_dao.g.dart';

@DriftAccessor(tables: [VideoTagPinPresetsTable])
class VideoTagPinPresetsDao extends DatabaseAccessor<AppDatabase>
    with _$VideoTagPinPresetsDaoMixin {
  VideoTagPinPresetsDao(super.db);

  Future<List<TagPlayPinPreset>> getAll() async {
    final rows = await (select(videoTagPinPresetsTable)
          ..orderBy([(t) => OrderingTerm(
                expression: t.createdAt,
                mode: OrderingMode.desc,
              )]))
        .get();
    return rows.map(TagPlayPinPresetAdapter.fromDb).toList(growable: false);
  }

  /// Creates or renames a preset. id == 0 inserts, otherwise updates.
  Future<int> save(TagPlayPinPreset preset) async {
    if (preset.id == 0) {
      return into(videoTagPinPresetsTable).insert(preset.toCompanion());
    }
    await (update(videoTagPinPresetsTable)
          ..where((t) => t.id.equals(preset.id)))
        .write(preset.toCompanion());
    return preset.id;
  }

  Future<void> deleteById(int id) {
    return (delete(videoTagPinPresetsTable)..where((t) => t.id.equals(id)))
        .go();
  }
}
