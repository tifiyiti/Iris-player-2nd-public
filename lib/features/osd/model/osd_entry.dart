import 'package:flutter/widgets.dart' show IconData;
import 'package:freezed_annotation/freezed_annotation.dart';

part 'osd_entry.freezed.dart';

/// Single OSD toast payload (PotPlayer-style, desktop-only).
@freezed
abstract class OsdEntry with _$OsdEntry {
  const factory OsdEntry({
    required String line1,
    String? line2,
    IconData? icon,
    double? progress, // 0..1, null = no bar (e.g. seek)
  }) = _OsdEntry;
}
