import 'package:flutter/services.dart';
import 'package:iris/features/windows/desktop_keyboard/model/potplayer_action.dart';

/// `;`-prefix sequence bindings — the conflict-free home for legacy features
/// that have no PotPlayer default key (function-driven assignment, SRS §5.3).
///
/// Followers are PLAIN keys only: a modified key press while buffered always
/// takes the pass-through path instead.
const LogicalKeyboardKey kSequencePrefixKey = LogicalKeyboardKey.semicolon;

/// How long a buffered `;` stays armed without a follower.
const Duration kSequenceBufferTimeout = Duration(seconds: 3);

/// `final`, not `const`: LogicalKeyboardKey overrides `==`, which Dart
/// forbids as a constant-map key type.
final Map<LogicalKeyboardKey, PotPlayerAction> kPotPlayerSequenceMap =
    <LogicalKeyboardKey, PotPlayerAction>{
  LogicalKeyboardKey.keyF: PotPlayerAction.storagesBrowser,
  LogicalKeyboardKey.keyH: PotPlayerAction.historyPanel,
  LogicalKeyboardKey.keyP: PotPlayerAction.togglePlaylistDockMode,
  LogicalKeyboardKey.keyR: PotPlayerAction.toggleRepeatMode,
  LogicalKeyboardKey.keyX: PotPlayerAction.toggleShuffleMode,
};
