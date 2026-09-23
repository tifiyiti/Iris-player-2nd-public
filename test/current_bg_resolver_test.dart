import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/background_playback/services/current_bg_resolver.dart';
import 'package:iris/models/file.dart';

FileItem _file(String name) => FileItem(name: name, uri: 'file:///$name');

/// The editor reports "no Sub Audio file" only when 副音 truly has nothing
/// loaded. A mapping-driven or just-opened file must still resolve.
void main() {
  group('resolveCurrentBgFile', () {
    test('the mapped segment file outranks the engine and the natural queue',
        () {
      final mapped = _file('mapped');
      final engine = _file('engine');
      final natural = _file('natural');
      expect(
        resolveCurrentBgFile(
          mappedFile: mapped,
          engineFile: engine,
          naturalFile: natural,
        ),
        mapped,
      );
    });

    test('falls back to the engine file when no mapping drives 副音', () {
      final engine = _file('engine');
      final natural = _file('natural');
      expect(
        resolveCurrentBgFile(
          mappedFile: null,
          engineFile: engine,
          naturalFile: natural,
        ),
        engine,
      );
    });

    test('falls back to the natural queue entry when the engine has no file',
        () {
      final natural = _file('natural');
      expect(
        resolveCurrentBgFile(
          mappedFile: null,
          engineFile: null,
          naturalFile: natural,
        ),
        natural,
      );
    });

    test('null only when all three sources are empty', () {
      expect(
        resolveCurrentBgFile(
          mappedFile: null,
          engineFile: null,
          naturalFile: null,
        ),
        isNull,
      );
    });
  });
}
