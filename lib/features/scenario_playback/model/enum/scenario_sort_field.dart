import 'package:iris/features/media_library/model/enum/basic_enum.dart';
import 'package:iris/features/media_library/model/enum/media_node.dart';

/// Sort fields supported by scenario resolution.
///
/// Sorting belongs to the Scenario (see playback scenario state),
/// not to the media database globally.
enum ScenarioSortField {
  name,
  modifiedAt,
  durationMs,
  sizeInBytes,
}

extension ScenarioSortFieldMapping on ScenarioSortField {
  /// The media-library sort column this scenario sort maps to.
  ///
  /// Shared by the folder source provider and `SharedMediaOrder` so the two can
  /// never disagree about which column an order is built on.
  MediaSortField toMediaSortField() {
    switch (this) {
      case ScenarioSortField.name:
        return MediaSortField.name;
      case ScenarioSortField.modifiedAt:
        return MediaSortField.modifiedAt;
      case ScenarioSortField.durationMs:
        return MediaSortField.durationMs;
      case ScenarioSortField.sizeInBytes:
        return MediaSortField.sizeInBytes;
    }
  }

  /// The direction a field reads best in when it is FIRST selected.
  ///
  /// Text reads A→Z; the numeric axes (time, duration, size) read
  /// newest/largest first. Re-selecting the SAME field still toggles — this only
  /// decides the direction of a field SWITCH.
  SortDirection get naturalDirection {
    switch (this) {
      case ScenarioSortField.name:
        return SortDirection.asc;
      case ScenarioSortField.modifiedAt:
      case ScenarioSortField.durationMs:
      case ScenarioSortField.sizeInBytes:
        return SortDirection.desc;
    }
  }
}
