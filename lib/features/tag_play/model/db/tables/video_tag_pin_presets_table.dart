import 'package:drift/drift.dart';

/// A named, saved snapshot of the global tag pin order ("pin 套装").
///
/// The CURRENT pin order lives with the app state (aux row `tagplay.pinOrder`);
/// presets are unlimited named restore points the user can apply in one tap.
class VideoTagPinPresetsTable extends Table {
  @override
  String get tableName => 'video_tag_pin_preset';

  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text().withLength(min: 1, max: 100)();

  /// JSON array of tag ids in pin order.
  TextColumn get pinnedTagIds => text().withDefault(const Constant('[]'))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
