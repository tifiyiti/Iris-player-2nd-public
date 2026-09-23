import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:iris/features/app_identity/model/domain/app_identity_entry.dart';

part 'app_identity_state.freezed.dart';

/// Reactive state of the app-identity feature.
@freezed
abstract class AppIdentityState with _$AppIdentityState {
  const factory AppIdentityState({
    /// All persisted entries, sorted by creation time.
    @Default(<AppIdentityEntry>[]) List<AppIdentityEntry> entries,

    /// Entry that last hijacked the SystemPlaying workspace.
    /// Null = default mode (no entry override in effect).
    String? activeEntryId,

    /// Platform capability probe result (pinning available on this device).
    @Default(false) bool supported,
  }) = _AppIdentityState;
}
