import 'package:freezed_annotation/freezed_annotation.dart';

part 'scan_state.freezed.dart';
part 'scan_state.g.dart';

@freezed
abstract class ScanState with _$ScanState {
  const factory ScanState({
    required String storageId,
    required List<String> path,
    required ScanStatus status,
    DateTime? lastScannedAt,
  }) = _ScanState;

  factory ScanState.fromJson(Map<String, dynamic> json) => _$ScanStateFromJson(json);
}

enum ScanStatus {
  notScanned,
  scanning,
  done,
}
