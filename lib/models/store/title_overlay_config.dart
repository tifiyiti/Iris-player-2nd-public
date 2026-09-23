import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:iris/l10n/app_localizations.dart';

part 'title_overlay_config.freezed.dart';
part 'title_overlay_config.g.dart';

enum TitleField {
  appIcon,
  battery,
  time,
  queueIndex,
  mediaName,
  ;

  bool get supportedOnDesktop => this != TitleField.battery;
}

@freezed
abstract class TitleOverlayConfig with _$TitleOverlayConfig {
  const factory TitleOverlayConfig({
    @Default(true) bool showAppIcon,
    @Default(true) bool showBattery,
    @Default(true) bool showTime,
    @Default(true) bool showQueueIndex,
    @Default(true) bool showMediaName,
    @Default(20.0) double fontSize,
  }) = _TitleOverlayConfig;

  factory TitleOverlayConfig.fromJson(Map<String, dynamic> json) => _$TitleOverlayConfigFromJson(json);
}

extension TitleFieldLocalization on TitleField {
  String label(AppLocalizations t) {
    switch (this) {
      case TitleField.appIcon:
        return t.title_field_app_icon;
      case TitleField.battery:
        return t.title_field_battery;
      case TitleField.time:
        return t.title_field_time;
      case TitleField.queueIndex:
        return t.title_field_queue_index;
      case TitleField.mediaName:
        return t.title_field_media_name;
    }
  }
}
