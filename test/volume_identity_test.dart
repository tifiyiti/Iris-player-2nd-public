import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/models/storages/volume_identity.dart';
import 'package:iris/widgets/popups/storages/db/storages_utils/storage_utils.dart';

/// Stable volume identity + id generation: the drive letter must not leak into
/// a local storage's identity when a volume id is known, and the platform
/// parsers must normalize the raw native forms.
void main() {
  group('normalizeWindowsVolumeName', () {
    test('extracts the GUID from a volume GUID path', () {
      expect(
        VolumeIdentity.normalizeWindowsVolumeName(r'\\?\Volume{abc-123}\'),
        'vol:abc-123',
      );
    });

    test('is case-insensitive and trims the trailing separator', () {
      expect(
        VolumeIdentity.normalizeWindowsVolumeName(r'\\?\Volume{ABCD-EF01}'),
        'vol:abcd-ef01',
      );
    });

    test('returns null for a non-GUID name', () {
      expect(VolumeIdentity.normalizeWindowsVolumeName('C:\\'), isNull);
    });
  });

  test('formatWindowsSerial renders an 8-hex-digit token', () {
    expect(VolumeIdentity.formatWindowsSerial(0x1234ABCD), 'serial:1234abcd');
    expect(VolumeIdentity.formatWindowsSerial(1), 'serial:00000001');
  });

  group('androidVolumeId', () {
    test('reads the volume segment from a mount path', () {
      expect(
        VolumeIdentity.androidVolumeId('/storage/ABCD-1234/Movies'),
        'vol:abcd-1234',
      );
    });

    test('reads the volume prefix from a SAF tree URI', () {
      expect(
        VolumeIdentity.androidVolumeId(
          'content://com.android.externalstorage.documents/tree/ABCD-1234%3AMovies',
        ),
        'vol:abcd-1234',
      );
    });

    test('treats emulated internal storage as a stable volume', () {
      expect(
        VolumeIdentity.androidVolumeId('/storage/emulated/0'),
        'vol:emulated',
      );
    });

    test('returns null for empty input', () {
      expect(VolumeIdentity.androidVolumeId('   '), isNull);
    });
  });

  test('debugResolver overrides the platform lookup', () async {
    VolumeIdentity.debugResolver = (root) async => 'vol:test';
    addTearDown(() => VolumeIdentity.debugResolver = null);
    expect(await VolumeIdentity.of('D:'), 'vol:test');
  });

  group('storage id decoupling', () {
    LocalStorage local({
      required String name,
      required List<String> basePath,
      String? volumeId,
    }) =>
        LocalStorage(
          type: StorageType.internal,
          name: name,
          basePath: basePath,
          volumeId: volumeId,
        );

    test('same volume under different letters yields the same id', () {
      final d = generateStorageId(
          local(name: 'Movies (D:)', basePath: ['D:'], volumeId: 'vol:g'));
      final e = generateStorageId(
          local(name: 'Movies (E:)', basePath: ['E:'], volumeId: 'vol:g'));
      expect(d, e);
    });

    test('different volumes yield different ids', () {
      final a = generateStorageId(
          local(name: 'A (D:)', basePath: ['D:'], volumeId: 'vol:a'));
      final b = generateStorageId(
          local(name: 'B (D:)', basePath: ['D:'], volumeId: 'vol:b'));
      expect(a, isNot(b));
    });

    test('without a volume id the id still depends on the letter', () {
      final d = generateStorageId(local(name: 'X (D:)', basePath: ['D:']));
      final e = generateStorageId(local(name: 'X (E:)', basePath: ['E:']));
      expect(d, isNot(e));
    });

    test('sub-path below the volume is part of the id', () {
      final whole = generateStorageId(
          local(name: 'X', basePath: ['D:'], volumeId: 'vol:g'));
      final sub = generateStorageId(
          local(name: 'X', basePath: ['D:', 'Movies'], volumeId: 'vol:g'));
      expect(whole, isNot(sub));
    });
  });

  group('volumeRelativeBase', () {
    test('whole Windows volume root is empty', () {
      expect(volumeRelativeBase(['D:']), '');
    });

    test('Windows sub-path is kept', () {
      expect(volumeRelativeBase(['D:', 'Movies']), 'Movies');
    });

    test('whole Android volume root is empty', () {
      expect(volumeRelativeBase(['/storage/ABCD-1234']), '');
    });

    test('Android sub-path is kept', () {
      expect(volumeRelativeBase(['/storage/ABCD-1234', 'Movies']), 'Movies');
    });
  });
}
