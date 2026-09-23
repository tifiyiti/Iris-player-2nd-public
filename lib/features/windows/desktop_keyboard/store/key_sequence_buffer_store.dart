import 'dart:async';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/features/windows/desktop_keyboard/controller/potplayer_sequence_map.dart';

part 'key_sequence_buffer_store.freezed.dart';

/// Ephemeral state of the `;` prefix-sequence buffer. Never persisted —
/// a buffering session is meaningless across restarts.
@freezed
abstract class KeySequenceBufferState with _$KeySequenceBufferState {
  const factory KeySequenceBufferState({
    @Default(false) bool isBuffering,
  }) = _KeySequenceBufferState;
}

/// Owns the armed/disarmed flag the waiting indicator (KeySequenceOverlay)
/// renders from and the timeout [Timer] whose deadline makes
/// [SequenceResolver] R5b reachable (see PotPlayerKeyExecutor).
class KeySequenceBufferStore extends Store<KeySequenceBufferState> {
  KeySequenceBufferStore() : super(const KeySequenceBufferState());

  Timer? _timer;
  DateTime? _openedAt;

  /// Real elapsed time since the buffer was armed; null when idle.
  /// Backs `resolveSequence` R5b (trailing key after timeout is swallowed).
  Duration? get elapsed =>
      _openedAt == null ? null : DateTime.now().difference(_openedAt!);

  void open() {
    _timer?.cancel();
    _openedAt = DateTime.now();
    set(state.copyWith(isBuffering: true));
    _timer = Timer(kSequenceBufferTimeout, () {
      _timer = null;
      _openedAt = null;
      set(const KeySequenceBufferState());
    });
  }

  void close() {
    _timer?.cancel();
    _timer = null;
    _openedAt = null;
    set(const KeySequenceBufferState());
  }

  /// Test-only alias: identical to [close] but keeps test code from reading
  /// like it tears the store down (the locator owns that lifecycle).
  void reset() => close();
}

KeySequenceBufferStore useKeySequenceBufferStore() =>
    create(() => KeySequenceBufferStore());
