import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:iris/features/background_playback/services/apb_edit_context.dart';

part 'use_apb_edit_session_store.freezed.dart';

@freezed
abstract class ApbEditSessionState with _$ApbEditSessionState {
  const factory ApbEditSessionState({ApbEditSession? session}) =
      _ApbEditSessionState;
}

/// Session-only holder of the active APB edit context. Kept out of
/// [BackgroundPlaybackState] so no persistence codegen touches a service type.
class ApbEditSessionStore extends Store<ApbEditSessionState> {
  ApbEditSessionStore() : super(const ApbEditSessionState());

  ApbEditSession? get session => state.session;

  void begin(ApbEditSession session) =>
      set(ApbEditSessionState(session: session));

  void clear() => set(const ApbEditSessionState());
}

ApbEditSessionStore useApbEditSessionStore() =>
    create(() => ApbEditSessionStore());

/// Restores the playback context that was active before the APB editor opened
/// and deletes the transient single-fg workspace. No-op when none is active.
Future<void> closeActiveApbEditSession() async {
  final store = useApbEditSessionStore();
  final session = store.session;
  if (session == null) return;
  store.clear();
  await ApbEditContext.exit(session);
}
