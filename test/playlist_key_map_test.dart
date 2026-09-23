import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/windows/desktop_keyboard/controller/potplayer_key_map.dart';
import 'package:iris/features/windows/desktop_keyboard/controller/playlist_key_map.dart';
import 'package:iris/features/windows/desktop_keyboard/model/playlist_action.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('kPotPlayerPlaylistMap', () {
    test('maps the PL > navigation / selection / playback keys', () {
      expect(kPotPlayerPlaylistMap[const KeyCombo(LogicalKeyboardKey.arrowUp)],
          PlaylistAction.cursorUp);
      expect(kPotPlayerPlaylistMap[const KeyCombo(LogicalKeyboardKey.arrowDown)],
          PlaylistAction.cursorDown);
      expect(kPotPlayerPlaylistMap[const KeyCombo(LogicalKeyboardKey.home)],
          PlaylistAction.cursorFirst);
      expect(kPotPlayerPlaylistMap[const KeyCombo(LogicalKeyboardKey.end)],
          PlaylistAction.cursorLast);
      expect(
          kPotPlayerPlaylistMap[
              const KeyCombo(LogicalKeyboardKey.keyA, ctrl: true)],
          PlaylistAction.selectAll);
      expect(
          kPotPlayerPlaylistMap[
              const KeyCombo(LogicalKeyboardKey.keyJ, ctrl: true)],
          PlaylistAction.invertSelection);
      expect(kPotPlayerPlaylistMap[const KeyCombo(LogicalKeyboardKey.keyP)],
          PlaylistAction.play);
    });

    test('maps the remove keys', () {
      expect(
          kPotPlayerPlaylistMap[const KeyCombo(LogicalKeyboardKey.delete)],
          PlaylistAction.removeSelected);
      expect(
          kPotPlayerPlaylistMap[
              const KeyCombo(LogicalKeyboardKey.delete, ctrl: true)],
          PlaylistAction.removeUnselected);
      expect(
          kPotPlayerPlaylistMap[
              const KeyCombo(LogicalKeyboardKey.keyT, ctrl: true)],
          PlaylistAction.removeMissing);
    });

    test('maps the sort-by keys', () {
      expect(
          kPotPlayerPlaylistMap[
              const KeyCombo(LogicalKeyboardKey.digit1, ctrl: true)],
          PlaylistAction.sortAscending);
      expect(
          kPotPlayerPlaylistMap[
              const KeyCombo(LogicalKeyboardKey.digit2, ctrl: true)],
          PlaylistAction.sortDescending);
      expect(
          kPotPlayerPlaylistMap[
              const KeyCombo(LogicalKeyboardKey.digit0, ctrl: true)],
          PlaylistAction.sortByFolder);
      expect(
          kPotPlayerPlaylistMap[
              const KeyCombo(LogicalKeyboardKey.digit6, ctrl: true)],
          PlaylistAction.sortBySize);
      expect(
          kPotPlayerPlaylistMap[
              const KeyCombo(LogicalKeyboardKey.digit7, ctrl: true)],
          PlaylistAction.sortByDuration);
      expect(
          kPotPlayerPlaylistMap[
              const KeyCombo(LogicalKeyboardKey.digit8, ctrl: true)],
          PlaylistAction.sortByDate);
      expect(
          kPotPlayerPlaylistMap[
              const KeyCombo(LogicalKeyboardKey.digit9, ctrl: true)],
          PlaylistAction.sortRandom);
    });

    test('keeps global player keys OUT of the playlist map', () {
      const globalOnly = [
        KeyCombo(LogicalKeyboardKey.space),
        KeyCombo(LogicalKeyboardKey.pageUp),
        KeyCombo(LogicalKeyboardKey.pageDown),
        KeyCombo(LogicalKeyboardKey.enter),
        KeyCombo(LogicalKeyboardKey.arrowLeft),
        KeyCombo(LogicalKeyboardKey.arrowRight),
        KeyCombo(LogicalKeyboardKey.f5),
      ];
      for (final combo in globalOnly) {
        expect(kPotPlayerPlaylistMap.containsKey(combo), isFalse,
            reason: 'global key must not be owned by the list: $combo');
      }
    });

    test('consumes unmappable PL actions as deliberate no-ops', () {
      expect(
          kPotPlayerPlaylistMap[
              const KeyCombo(LogicalKeyboardKey.keyV, ctrl: true)],
          PlaylistAction.paste);
      expect(
          kPotPlayerPlaylistMap[
              const KeyCombo(LogicalKeyboardKey.keyR, ctrl: true)],
          PlaylistAction.albumEdit);
    });
  });

  group('isPlaylistTypeAheadKey', () {
    KeyEvent keyDown(LogicalKeyboardKey key) => KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyA,
          logicalKey: key,
          timeStamp: Duration.zero,
        );

    test('accepts bare letters and digits', () {
      expect(isPlaylistTypeAheadKey(keyDown(LogicalKeyboardKey.keyD)), isTrue);
      expect(isPlaylistTypeAheadKey(keyDown(LogicalKeyboardKey.digit3)), isTrue);
    });

    test('rejects Space / Enter / Delete and modified keys', () {
      expect(isPlaylistTypeAheadKey(keyDown(LogicalKeyboardKey.space)), isFalse);
      expect(isPlaylistTypeAheadKey(keyDown(LogicalKeyboardKey.enter)), isFalse);
      expect(
          isPlaylistTypeAheadKey(keyDown(LogicalKeyboardKey.delete)), isFalse);
    });

    test('exempts the speed keys so player Z/X/C stay live', () {
      // The list must not capture these as type-ahead; otherwise the global
      // handler never sees them and the speed keys die while the queue holds
      // focus (they are the only plain letters removed from ownership).
      for (final key in <LogicalKeyboardKey>[
        LogicalKeyboardKey.keyZ,
        LogicalKeyboardKey.keyX,
        LogicalKeyboardKey.keyC,
      ]) {
        expect(isPlaylistTypeAheadKey(keyDown(key)), isFalse,
            reason: 'speed key must reach the global player handler: $key');
      }
      // A non-speed letter is still type-ahead.
      expect(isPlaylistTypeAheadKey(keyDown(LogicalKeyboardKey.keyD)), isTrue);
    });
  });
}
